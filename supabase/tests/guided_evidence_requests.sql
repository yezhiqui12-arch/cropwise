begin;
create temp table evidence_checks(result text);
do $$
declare c public.expert_cases%rowtype; a public.assessments%rowtype; expert uuid; block_id uuid; seq integer;
 request_id uuid:=gen_random_uuid(); returned_id uuid; renewal_id uuid:=gen_random_uuid(); reply_id uuid:=gen_random_uuid(); photo_id uuid:=gen_random_uuid(); photo_path text; payload jsonb; rating public.expert_plant_severity%rowtype;
begin
 select ec.* into c from public.expert_cases ec join public.assessments aa on aa.id=ec.assessment_id
 where aa.protocol_version='wormwise-da-scattered-20-v1' and ec.evidence_photo_consent and not exists(select 1 from public.expert_severity_summaries s where s.case_id=ec.id) limit 1;
 if c.id is null then raise exception 'No unfinished current DA case for rollback checks'; end if;
 select user_id into expert from public.profiles where account_kind='expert' and user_id<>c.owner_id limit 1;
 if expert is null then raise exception 'No expert for rollback check'; end if;
 select * into a from public.assessments where id=c.assessment_id;
 block_id:=(a.result_snapshot->'sampling_routes'->0->>'block_run_id')::uuid;
 seq:=coalesce((a.result_snapshot->'sampling_routes'->0->>'block_sequence')::integer,1);
 perform set_config('request.jwt.claim.sub',(select user_id::text from public.profiles where account_kind='admin' limit 1),true);
 update public.expert_cases set claimed_by=expert,status='claimed' where id=c.id;
 perform set_config('request.jwt.claim.sub',expert::text,true);
 if has_function_privilege('anon','public.request_plant_evidence(uuid,uuid,uuid,integer,text,jsonb,text,text)','execute') then raise exception 'Public access'; end if;
 insert into evidence_checks values('Request RPC requires authenticated participant access');
 begin
   perform public.request_plant_evidence(request_id,c.id,block_id,21,'blurry','["whorl"]','Need clearer photos');
   raise exception 'Invalid plant accepted';
 exception when others then if sqlerrm not like '%Choose a current sampled plant%' then raise; end if; end;
 insert into evidence_checks values('Out-of-range plant rejected');
 begin
   perform public.request_plant_evidence(request_id,c.id,gen_random_uuid(),8,'blurry','["whorl"]','Need clearer photos');
   raise exception 'Wrong block accepted';
 exception when others then if sqlerrm not like '%sampling block%' then raise; end if; end;
 insert into evidence_checks values('Foreign sampling block rejected');
 perform set_config('request.jwt.claim.sub',c.owner_id::text,true);
 begin
   perform public.request_plant_evidence(request_id,c.id,block_id,8,'blurry','["whorl"]','Need clearer photos');
   raise exception 'Farmer requested as expert';
 exception when others then if sqlerrm not like '%Assigned expert%' then raise; end if; end;
 insert into evidence_checks values('Farmer cannot impersonate assigned expert');
 perform set_config('request.jwt.claim.sub',expert::text,true);
 -- Synthetic photo identity exists only within this rolled-back transaction.
 insert into public.evidence_files(id,owner_id,assessment_id,storage_path,station_number,plant_number,block_run_id,block_sequence,mime_type)
 values(gen_random_uuid(),c.owner_id,c.assessment_id,'rollback-only/plant8.jpg',8,1,block_id,seq,'image/jpeg');
 perform public.save_expert_plant_severity_v3(c.id,8,1,'scored',3,'Original note','fresh',block_id);
 returned_id:=public.request_plant_evidence(request_id,c.id,block_id,8,'blurry','["whole_plant","whorl"]','Please send clear photos of this same plant.');
 if returned_id<>request_id or (select evidence_request_status from public.case_messages where id=request_id)<>'awaiting_photos' then raise exception 'Request not created'; end if;
 select * into rating from public.expert_plant_severity where case_id=c.id and block_run_id is not distinct from block_id and station_number=8 and plant_number=1;
 if rating.outcome<>'insufficient_evidence' or rating.davis_score is not null or rating.note<>'Original note' then raise exception 'Old rating not invalidated safely'; end if;
 insert into evidence_checks values('Request and insufficient outcome saved together; previous note retained');
 returned_id:=public.request_plant_evidence(gen_random_uuid(),c.id,block_id,8,'too_dark','["whorl"]','Duplicate request');
 if returned_id<>request_id then raise exception 'Duplicate request'; end if;
 insert into evidence_checks values('Outstanding request reused for duplicate and retry');
 begin
   insert into public.expert_severity_summaries(case_id) values(c.id);
   raise exception 'Finalization accepted while request outstanding';
 exception when others then if sqlerrm not like '%Resolve all plant evidence requests%' then raise; end if; end;
 insert into evidence_checks values('Outstanding request blocks finalization');
 photo_path:=c.id::text||'/'||c.owner_id::text||'/'||reply_id::text||'/'||photo_id::text||'.jpg';
 insert into storage.objects(bucket_id,name,metadata) values('case-message-images',photo_path,'{"mimetype":"image/jpeg","size":1234}');
 perform set_config('request.jwt.claim.sub',c.owner_id::text,true);
 payload:=jsonb_build_array(jsonb_build_object('storage_path',photo_path,'station_number',9,'plant_number',1,'block_run_id',block_id,'same_plant_confirmed',true));
 begin
   perform public.send_case_message(reply_id,c.id,'Replacement',payload,'message',null,null,request_id);
   raise exception 'Wrong plant accepted';
 exception when others then if sqlerrm not like '%Photo identity does not match%' then raise; end if; end;
 insert into evidence_checks values('Wrong-plant attachment rejected by server');
 payload:=jsonb_build_array(jsonb_build_object('storage_path',photo_path));
 begin
   perform public.send_case_message(reply_id,c.id,'Replacement',payload,'message',null,null,request_id);
   raise exception 'Missing confirmation accepted';
 exception when others then if sqlerrm not like '%Confirm that these photos%' then raise; end if; end;
 insert into evidence_checks values('Same-plant confirmation required');
 payload:=jsonb_build_array(jsonb_build_object('storage_path',photo_path,'same_plant_confirmed',true,'capture_source','gallery','quality_warnings','["tooDark"]'::jsonb));
 perform public.send_case_message(reply_id,c.id,'Replacement',payload,'message',null,null,request_id);
 if (select evidence_request_status from public.case_messages where id=request_id)<>'photos_received' then raise exception 'Request resolved too early'; end if;
 if not exists(select 1 from public.evidence_files where id=photo_id and station_number=8 and plant_number=1 and block_run_id is not distinct from block_id and source_message_id=reply_id and captured_at is null and received_at is not null and quality_warnings='["tooDark"]' and same_plant_confirmed) then raise exception 'Identity or provenance lost'; end if;
 insert into evidence_checks values('Reply inherits request identity; unknown capture time and server receipt preserved');
 returned_id:=public.send_case_message(reply_id,c.id,'Replacement',payload,'message',null,null,request_id);
 if returned_id<>reply_id or (select count(*) from public.evidence_files where id=photo_id)<>1 then raise exception 'Reply duplicated'; end if;
 insert into evidence_checks values('Upload acknowledgement retry does not duplicate evidence');
 perform set_config('request.jwt.claim.sub',expert::text,true);
 perform public.save_expert_plant_severity_v3(c.id,8,1,'scored',3,'Review needs freshness','uncertain',block_id);
 if (select evidence_request_status from public.case_messages where id=request_id)<>'photos_received' then raise exception 'Uncertain review resolved'; end if;
 insert into evidence_checks values('Uncertain freshness leaves request unresolved');
 returned_id:=public.request_plant_evidence(renewal_id,c.id,block_id,8,'too_dark','["whorl"]','Please retake the whorl in better lighting');
 if returned_id<>request_id or (select evidence_request_status from public.case_messages where id=request_id)<>'awaiting_photos'
   or not exists(select 1 from public.case_messages where id=renewal_id and request_message_id=request_id) then raise exception 'Renewal lost audit trail'; end if;
 insert into evidence_checks values('Unusable replacement can renew same plant request with follow-up audit message');
 returned_id:=public.request_plant_evidence(renewal_id,c.id,block_id,8,'too_dark','["whorl"]','Retry');
 if returned_id<>request_id or (select count(*) from public.case_messages where id=renewal_id)<>1 then raise exception 'Renewal duplicated'; end if;
 insert into evidence_checks values('Renewal retry does not duplicate requests or follow-up messages');
 perform public.save_expert_plant_severity_v3(c.id,8,1,'scored',0,'Old photos not sufficient',null,block_id);
 if (select evidence_request_status from public.case_messages where id=request_id)<>'awaiting_photos' then raise exception 'Awaiting request resolved from old photos'; end if;
 insert into evidence_checks values('Scoring old photos cannot resolve a renewed request awaiting evidence');
 reply_id:=gen_random_uuid(); photo_id:=gen_random_uuid();
 photo_path:=c.id::text||'/'||c.owner_id::text||'/'||reply_id::text||'/'||photo_id::text||'.jpg';
 insert into storage.objects(bucket_id,name,metadata) values('case-message-images',photo_path,'{"mimetype":"image/jpeg","size":100}'::jsonb);
 perform set_config('request.jwt.claim.sub',c.owner_id::text,true);
 perform public.send_case_message(reply_id,c.id,'Clearer replacement',jsonb_build_array(jsonb_build_object('storage_path',photo_path,'same_plant_confirmed',true)),'message',null,null,request_id);
 perform set_config('request.jwt.claim.sub',expert::text,true);
 perform public.save_expert_plant_severity_v3(c.id,8,1,'scored',0,'Reassessed',null,block_id);
 if (select evidence_request_status from public.case_messages where id=request_id)<>'resolved' then raise exception 'Request not resolved'; end if;
 insert into evidence_checks values('Expert reassessment resolves request');
 -- Choose another plant; request may be made even when no evidence/rating exists.
 returned_id:=public.request_plant_evidence(gen_random_uuid(),c.id,block_id,20,'missing_photos','["whole_plant"]','Please provide the missing plant photo');
 if returned_id is null then raise exception 'Missing-plant request failed'; end if;
 insert into evidence_checks values('A planned missing plant can receive a targeted request');
end;
$$;
select jsonb_build_object('passed',count(*),'checks',jsonb_agg(result),'data changes','rolled back') as evidence_request_verification from evidence_checks;
rollback;
