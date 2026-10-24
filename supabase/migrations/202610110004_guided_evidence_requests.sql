begin;
alter table public.case_messages
 add column if not exists requested_block_run_id uuid,
 add column if not exists requested_block_sequence integer,
 add column if not exists evidence_reason text,
 add column if not exists requested_views jsonb not null default '[]'::jsonb,
 add column if not exists evidence_request_status text check (evidence_request_status in ('awaiting_photos','photos_received','resolved'));
alter table public.evidence_files
 add column if not exists capture_source text,
 add column if not exists received_at timestamptz,
 add column if not exists quality_warnings jsonb not null default '[]'::jsonb,
 add column if not exists same_plant_confirmed boolean not null default false;
alter table public.evidence_files alter column received_at set default clock_timestamp();
create unique index if not exists one_open_plant_evidence_request on public.case_messages
 (case_id,coalesce(requested_block_run_id,'00000000-0000-0000-0000-000000000000'::uuid),requested_station,requested_plant)
 where evidence_request_status in ('awaiting_photos','photos_received');
drop policy if exists messages_participant_insert on public.case_messages;
create policy messages_participant_insert on public.case_messages for insert to authenticated
 with check(sender_id=auth.uid() and public.can_send_case_message(case_id)
 and attachments='[]'::jsonb and message_kind='message' and requested_station is null
 and requested_plant is null and request_message_id is null and requested_block_run_id is null
 and requested_block_sequence is null and evidence_reason is null and requested_views='[]'::jsonb
 and evidence_request_status is null);
create or replace function public.send_case_message(
  p_message_id uuid, p_case_id uuid, p_body text,
  p_attachments jsonb default '[]'::jsonb, p_kind text default 'message',
  p_requested_station integer default null, p_requested_plant integer default null,
  p_request_message_id uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_case public.expert_cases;
  v_existing public.case_messages;
  v_request public.case_messages;
  v_source text;
  v_captured timestamptz;
  v_warnings jsonb;
  v_attachment jsonb;
  v_clean jsonb := '[]'::jsonb;
  v_path text;
  v_station integer;
  v_plant integer;
  v_body text := trim(coalesce(p_body,''));
  v_owner boolean;
  v_role text;
  v_assessment public.assessments%rowtype;
  v_routes jsonb;
  v_block uuid;
  v_sequence integer;
  v_da boolean;
  v_evidence_id uuid;
begin
  if auth.uid() is null or p_message_id is null then raise exception 'Sign in to send a message'; end if;
  select * into v_case from public.expert_cases where id = p_case_id for update;
  v_owner := v_case.owner_id = auth.uid();
  select * into v_existing from public.case_messages where id = p_message_id;
  if v_existing.id is not null then
    if v_existing.case_id = p_case_id and v_existing.sender_id = auth.uid() then
      return v_existing.id; -- A retry after lost acknowledgement cannot duplicate.
    end if;
    raise exception 'Message identifier is already in use';
  end if;
  if not public.can_send_case_message(p_case_id) then raise exception 'An open case and participant access are required'; end if;
  if p_kind not in ('message','evidence_request') or (p_kind = 'evidence_request' and v_owner) then
    raise exception 'Only the assigned expert or admin can request evidence';
  end if;
  if p_attachments is null or jsonb_typeof(p_attachments) <> 'array' then raise exception 'Invalid attachments'; end if;
  if jsonb_array_length(p_attachments) > 5 then raise exception 'Attach at most five photos'; end if;
  if char_length(v_body) > 8000 or (v_body = '' and jsonb_array_length(p_attachments) = 0)
    or (p_kind = 'evidence_request' and v_body = '') then raise exception 'Add a message or photo'; end if;
  if (p_requested_station is not null and p_requested_station <= 0)
    or (p_requested_plant is not null and (p_requested_plant <= 0 or p_requested_station is null)) then
    raise exception 'Choose a positive station and plant number';
  end if;
  if p_request_message_id is not null and not exists (select 1 from public.case_messages m
    where m.id = p_request_message_id and m.case_id = p_case_id and m.message_kind = 'evidence_request'
    and m.is_farmer_visible) then raise exception 'Evidence request must belong to this case'; end if;
  if p_request_message_id is not null then
    select * into v_request from public.case_messages where id=p_request_message_id;
    if v_request.evidence_request_status is not null then
      if not v_owner or v_request.evidence_request_status='resolved'
        or exists(select 1 from public.expert_severity_summaries where case_id=p_case_id)
        then raise exception 'This plant request is no longer accepting evidence'; end if;
    end if;
  end if;
  select * into v_assessment from public.assessments where id=v_case.assessment_id;
  v_da := v_assessment.protocol_version='wormwise-da-scattered-20-v1';
  v_routes := coalesce(v_assessment.result_snapshot->'sampling_routes','[]'::jsonb);
  if jsonb_typeof(v_routes)<>'array' then v_routes := '[]'::jsonb; end if;
  v_role := case when v_owner then 'field_evidence' else 'expert_reference' end;
  for v_attachment in select value from jsonb_array_elements(p_attachments) loop
    v_path := v_attachment->>'storage_path';
    if v_path is null or v_path !~ ('^' || p_case_id::text || '/' || auth.uid()::text || '/' || p_message_id::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$')
      or exists (select 1 from jsonb_array_elements(v_clean) a where a->>'storage_path' = v_path) then
      raise exception 'Invalid or duplicate attachment path';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'case-message-images' and o.name = v_path
      and o.metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')
      and (o.metadata->>'size')::bigint between 1 and 10485760) then
      raise exception 'Upload each photo before sending (maximum 10 MB)';
    end if;
    v_station := nullif(v_attachment->>'station_number','')::integer;
    v_plant := nullif(v_attachment->>'plant_number','')::integer;
    if (v_station is not null and v_station <= 0) or
      (v_plant is not null and (v_plant <= 0 or v_station is null)) then raise exception 'Invalid photo station or plant number'; end if;
    if char_length(coalesce(v_attachment->>'caption','')) > 500 then raise exception 'Photo caption is too long'; end if;
    v_block := nullif(v_attachment->>'block_run_id','')::uuid;
    if v_request.evidence_request_status is not null then
      if (v_station is not null and v_station<>v_request.requested_station)
        or (v_plant is not null and v_plant<>v_request.requested_plant)
        or (v_block is not null and v_block is distinct from v_request.requested_block_run_id)
        then raise exception 'Photo identity does not match the requested block and plant'; end if;
      if v_attachment->'same_plant_confirmed' is distinct from 'true'::jsonb
        then raise exception 'Confirm that these photos show the requested sampled plant'; end if;
      v_station := v_request.requested_station;
      v_plant := v_request.requested_plant;
      v_block := v_request.requested_block_run_id;
    end if;
    v_source := coalesce(v_attachment->>'capture_source','unknown');
    if v_source not in ('camera','gallery','saved_assessment','unknown') then raise exception 'Invalid photo source'; end if;
    v_captured := nullif(v_attachment->>'captured_at','')::timestamptz;
    if v_captured > clock_timestamp()+interval '5 minutes' then raise exception 'Photo capture time is in the future'; end if;
    v_warnings := coalesce(v_attachment->'quality_warnings','[]'::jsonb);
    if jsonb_typeof(v_warnings)<>'array' or jsonb_array_length(v_warnings)>5 then raise exception 'Invalid quality warnings'; end if;
    if exists(select 1 from jsonb_array_elements_text(v_warnings) w where w not in
      ('lowSourceResolution','unexpectedUpscaling','possibleBlur','tooDark','possibleOverexposureOrGlare','qualityCheckUnavailable'))
      then raise exception 'Invalid quality warning'; end if;

    v_sequence := null;
    if v_da and v_plant is not null then
      if v_plant<>1 or v_station not between 1 and 20 then
        raise exception 'Choose a sampled plant from 1 to 20';
      end if;
      if v_block is null and jsonb_array_length(v_routes)=1 then
        v_block := (v_routes->0->>'block_run_id')::uuid;
      end if;
      if jsonb_array_length(v_routes)>0 then
        select coalesce((r->>'block_sequence')::integer,ordinality::integer) into v_sequence
          from jsonb_array_elements(v_routes) with ordinality rr(r,ordinality)
          where r->>'block_run_id'=v_block::text;
        if v_sequence is null then raise exception 'Choose the sampled plant sampling block'; end if;
      elsif v_block is not null or public.expert_assessment_has_multiple_blocks(v_case.assessment_id) then
        raise exception 'Sync sampling blocks before linking replacement evidence';
      end if;
    end if;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object(
      'storage_path',v_path,'caption',coalesce(v_attachment->>'caption',''),
      'station_number',v_station,'plant_number',v_plant,'purpose',v_role,
      'block_run_id',v_block,'block_sequence',v_sequence,
      'capture_source',v_source,'captured_at',v_captured,'received_at',clock_timestamp(),
      'same_plant_confirmed',coalesce(v_attachment->'same_plant_confirmed','false'::jsonb),
      'quality_warnings',v_warnings));
  end loop;
  insert into public.case_messages(id,case_id,sender_id,body,is_farmer_visible,
    attachments,message_kind,requested_station,requested_plant,request_message_id)
  values(p_message_id,p_case_id,auth.uid(),v_body,true,v_clean,p_kind,
    p_requested_station,p_requested_plant,p_request_message_id);
  if v_da and v_owner and v_case.evidence_photo_consent and
      not exists(select 1 from public.expert_severity_summaries s where s.case_id=p_case_id) then
    for v_attachment in select value from jsonb_array_elements(v_clean) loop
      if v_attachment->>'plant_number' is null then continue; end if;
      v_path := v_attachment->>'storage_path';
      v_evidence_id := split_part(regexp_replace(v_path,'^.*/',''),'.',1)::uuid;
      insert into public.evidence_files(id,owner_id,assessment_id,storage_path,storage_bucket,
        station_number,plant_number,mime_type,block_run_id,block_sequence,source_message_id,
        capture_source,captured_at,received_at,quality_warnings,same_plant_confirmed)
      select v_evidence_id,auth.uid(),v_case.assessment_id,v_path,'case-message-images',
        (v_attachment->>'station_number')::integer,(v_attachment->>'plant_number')::integer,
        o.metadata->>'mimetype',(v_attachment->>'block_run_id')::uuid,
        (v_attachment->>'block_sequence')::integer,p_message_id,
        v_attachment->>'capture_source',(v_attachment->>'captured_at')::timestamptz,
        (v_attachment->>'received_at')::timestamptz,v_attachment->'quality_warnings',
        (v_attachment->>'same_plant_confirmed')::boolean
      from storage.objects o where o.bucket_id='case-message-images' and o.name=v_path;
      -- A new photo requires the expert to reassess this plant. Preserve notes.
      update public.expert_plant_severity r set outcome='insufficient_evidence',
        davis_score=null,damage_freshness=null
      where r.case_id=p_case_id and r.station_number=(v_attachment->>'station_number')::integer
        and r.plant_number=(v_attachment->>'plant_number')::integer
        and r.block_run_id is not distinct from (v_attachment->>'block_run_id')::uuid;
    end loop;
  end if;
  if v_request.evidence_request_status is not null and jsonb_array_length(v_clean)>0 then
    update public.case_messages set evidence_request_status='photos_received' where id=p_request_message_id;
  end if;
  if p_kind = 'evidence_request' then
    update public.expert_cases set status='needs_information',updated_at=now() where id=p_case_id;
  end if;
  return p_message_id;
end;
$$;


create or replace function public.request_plant_evidence(
 p_message_id uuid,p_case_id uuid,p_block_run_id uuid,p_station_number integer,
 p_reason text,p_views jsonb,p_body text,p_note text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.expert_cases%rowtype; a public.assessments%rowtype; r jsonb; seq integer; existing_id uuid; existing_status text;
begin
 select * into c from public.expert_cases where id=p_case_id for update;
 if c.id is null or c.claimed_by is distinct from auth.uid() or c.status='closed' or not c.evidence_photo_consent
   or not exists(select 1 from public.profiles where user_id=auth.uid() and account_kind='expert')
   then raise exception 'Assigned expert access to shared evidence is required'; end if;
 if exists(select 1 from public.expert_severity_summaries where case_id=p_case_id)
   then raise exception 'Finalized reviews cannot request replacement evidence'; end if;
 select * into a from public.assessments where id=c.assessment_id;
 if a.protocol_version is distinct from 'wormwise-da-scattered-20-v1' or p_station_number is null
   or p_station_number not between 1 and 20 then raise exception 'Choose a current sampled plant from 1 to 20'; end if;
 r := coalesce(a.result_snapshot->'sampling_routes','[]'::jsonb);
 if jsonb_typeof(r)<>'array' then raise exception 'Sync the sampling plan'; end if;
 if jsonb_array_length(r)>0 then
   select coalesce((value->>'block_sequence')::integer,ordinality::integer) into seq
     from jsonb_array_elements(r) with ordinality where value->>'block_run_id'=p_block_run_id::text;
   if seq is null then raise exception 'Choose a sampling block in this assessment'; end if;
 elsif p_block_run_id is not null or public.expert_assessment_has_multiple_blocks(c.assessment_id) then
   raise exception 'Sync sampling blocks before requesting evidence';
 else seq := 1;
 end if;
 if p_reason is null or p_reason not in ('blurry','too_dark','wrong_view','plant_hidden','missing_photos','other')
   or p_views is null or jsonb_typeof(p_views)<>'array' or jsonb_array_length(p_views) not between 1 and 3
   then raise exception 'Choose a reason and the photos needed'; end if;
 if exists(select 1 from jsonb_array_elements_text(p_views) v where v not in ('whole_plant','whorl','damage_close_up'))
   then raise exception 'Invalid requested photo view'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Note is too long'; end if;
 if trim(coalesce(p_body,''))='' or length(p_body)>8000 then raise exception 'Add instructions (maximum 8000 characters)'; end if;
 -- Retry and concurrent requests reuse the outstanding request without invalidating received photos.
 select id,evidence_request_status into existing_id,existing_status from public.case_messages where case_id=p_case_id
   and requested_block_run_id is not distinct from p_block_run_id and requested_station=p_station_number
   and requested_plant=1 and evidence_request_status in ('awaiting_photos','photos_received');
 if existing_id is not null then
   if p_message_id=existing_id then return existing_id; end if;
   if existing_status='photos_received' then
     if exists(select 1 from public.case_messages where id=p_message_id) then
       if exists(select 1 from public.case_messages where id=p_message_id and case_id=p_case_id
         and sender_id=auth.uid() and request_message_id=existing_id) then return existing_id; end if;
       raise exception 'Message identifier is already in use';
     end if;
     -- Append a follow-up message for the audit trail and reuse the same plant request.
     perform public.send_case_message(p_message_id,p_case_id,
       'Clearer photos requested again — Block '||seq||', Plant '||p_station_number||': '||p_body,
       '[]'::jsonb,'message',null,null,null);
     update public.case_messages set request_message_id=existing_id where id=p_message_id;
     update public.case_messages set body=trim(p_body),evidence_reason=p_reason,
       requested_views=p_views,evidence_request_status='awaiting_photos' where id=existing_id;
     perform public.save_expert_plant_severity_v3(p_case_id,p_station_number,1,'insufficient_evidence',null,
       case when p_note='' then coalesce((select note from public.expert_plant_severity where case_id=p_case_id
         and block_run_id is not distinct from p_block_run_id and station_number=p_station_number and plant_number=1),'') else p_note end,
       null,p_block_run_id);
     update public.expert_cases set status='needs_information',updated_at=now() where id=p_case_id;
   end if;
   return existing_id;
 end if;
 if exists(select 1 from public.case_messages where id=p_message_id) then
   select id into existing_id from public.case_messages where id=p_message_id and case_id=p_case_id
     and sender_id=auth.uid() and requested_station=p_station_number
     and requested_block_run_id is not distinct from p_block_run_id and evidence_request_status is not null;
   if existing_id is null then raise exception 'Message identifier is already in use'; end if;
   return existing_id;
 end if;
 perform public.send_case_message(p_message_id,p_case_id,p_body,'[]'::jsonb,'evidence_request',p_station_number,1,null);
 update public.case_messages set requested_block_run_id=p_block_run_id,requested_block_sequence=seq,
   evidence_reason=p_reason,requested_views=p_views,evidence_request_status='awaiting_photos' where id=p_message_id;
 if exists(select 1 from public.evidence_files where assessment_id=c.assessment_id
   and block_run_id is not distinct from p_block_run_id and station_number=p_station_number and plant_number=1) then
   perform public.save_expert_plant_severity_v3(p_case_id,p_station_number,1,'insufficient_evidence',null,
     case when p_note='' then coalesce((select note from public.expert_plant_severity where case_id=p_case_id
       and block_run_id is not distinct from p_block_run_id and station_number=p_station_number and plant_number=1),'') else p_note end,
     null,p_block_run_id);
 end if;
 -- Missing plants intentionally have no invented rating until actual photos arrive.
 return p_message_id;
end;
$$;
revoke all on function public.request_plant_evidence(uuid,uuid,uuid,integer,text,jsonb,text,text) from public;
grant execute on function public.request_plant_evidence(uuid,uuid,uuid,integer,text,jsonb,text,text) to authenticated;

create or replace function public.resolve_plant_evidence_request()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.outcome='scored' and new.davis_score is not null
   and (new.davis_score=0 or new.damage_freshness in ('fresh','old_only')) then
   update public.case_messages set evidence_request_status='resolved'
     where case_id=new.case_id and requested_block_run_id is not distinct from new.block_run_id
       and requested_station=new.station_number and requested_plant=new.plant_number
       and evidence_request_status='photos_received';
 end if;
 return new;
end;
$$;
drop trigger if exists resolve_plant_evidence_request on public.expert_plant_severity;
create trigger resolve_plant_evidence_request after insert or update on public.expert_plant_severity
 for each row execute function public.resolve_plant_evidence_request();
create or replace function public.require_resolved_evidence_requests()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.case_messages where case_id=new.case_id
   and evidence_request_status in ('awaiting_photos','photos_received')) then
   raise exception 'Resolve all plant evidence requests before finalizing'; end if;
 return new;
end;
$$;
drop trigger if exists require_resolved_evidence_requests on public.expert_severity_summaries;
create trigger require_resolved_evidence_requests before insert on public.expert_severity_summaries
 for each row execute function public.require_resolved_evidence_requests();
revoke all on function public.resolve_plant_evidence_request() from public;
revoke all on function public.require_resolved_evidence_requests() from public;
notify pgrst,'reload schema';
commit;
