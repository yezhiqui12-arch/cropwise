-- Apply after 202610060001_block_scoped_expert_severity.sql.
-- New DA finalizations require the complete 20-plant plan and assessable freshness.
-- Historical finalized summaries are not recomputed or rewritten.
begin;
alter table public.expert_severity_summaries
  add column if not exists reporting_version integer,
  add column if not exists planned_plants integer,
  add column if not exists latest_evidence_at timestamptz;

-- Photo replies are published atomically with their validated plant identity.
-- Capture time is unknown for chat/gallery photos; received time is explicit.
alter table public.evidence_files
  add column if not exists storage_bucket text not null default 'assessment-evidence',
  add column if not exists source_message_id uuid references public.case_messages(id);

create or replace function public.send_case_message(
  p_message_id uuid, p_case_id uuid, p_body text,
  p_attachments jsonb default '[]'::jsonb, p_kind text default 'message',
  p_requested_station integer default null, p_requested_plant integer default null,
  p_request_message_id uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_case public.expert_cases;
  v_existing public.case_messages;
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
      'block_run_id',v_block,'block_sequence',v_sequence));
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
        station_number,plant_number,mime_type,block_run_id,block_sequence,source_message_id)
      select v_evidence_id,auth.uid(),v_case.assessment_id,v_path,'case-message-images',
        (v_attachment->>'station_number')::integer,(v_attachment->>'plant_number')::integer,
        o.metadata->>'mimetype',(v_attachment->>'block_run_id')::uuid,
        (v_attachment->>'block_sequence')::integer,p_message_id
      from storage.objects o where o.bucket_id='case-message-images' and o.name=v_path;
      -- A new photo requires the expert to reassess this plant. Preserve notes.
      update public.expert_plant_severity r set outcome='insufficient_evidence',
        davis_score=null,damage_freshness=null
      where r.case_id=p_case_id and r.station_number=(v_attachment->>'station_number')::integer
        and r.plant_number=(v_attachment->>'plant_number')::integer
        and r.block_run_id is not distinct from (v_attachment->>'block_run_id')::uuid;
    end loop;
  end if;
  if p_kind = 'evidence_request' then
    update public.expert_cases set status='needs_information',updated_at=now() where id=p_case_id;
  end if;
  return p_message_id;
end;
$$;

create or replace function public.finalize_expert_severity_review(p_case_id uuid)
returns public.expert_severity_summaries language plpgsql security definer set search_path='' as $$
declare c public.expert_cases%rowtype; result public.expert_severity_summaries%rowtype;
  total integer; reviewed integer; missing integer; expected integer; is_da boolean; a public.assessments%rowtype; routes jsonb; route_count integer; area_blocks integer; latest_evidence timestamptz; stats jsonb; points jsonb; blocks jsonb; assessed timestamptz; reviewer text;
begin
  select * into c from public.expert_cases where id=p_case_id for update;
  if c.id is null or c.claimed_by is distinct from auth.uid() or c.status='closed' or not c.evidence_photo_consent
    or not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.account_kind='expert') then raise exception 'Assigned expert access to an open case with shared evidence is required'; end if;
  select * into result from public.expert_severity_summaries where case_id=p_case_id;
  if result.case_id is not null then return result; end if;
  select * into a from public.assessments where id=c.assessment_id;
  is_da := a.protocol_version='wormwise-da-scattered-20-v1';
  if is_da then
    if a.completed_at is null then raise exception 'Complete the field assessment before finalizing'; end if;
    routes := coalesce(a.result_snapshot->'sampling_routes','[]'::jsonb);
    if jsonb_typeof(routes)<>'array' then raise exception 'Sampling block identities are unavailable'; end if;
    if exists(select 1 from jsonb_array_elements(routes) r where nullif(r->>'block_run_id','') is null)
      or (select count(*) from jsonb_array_elements(routes)) <> (select count(distinct r->>'block_run_id') from jsonb_array_elements(routes) r)
      then raise exception 'Sync unique sampling block identities before finalizing'; end if;
    select count(*)::integer into route_count from jsonb_array_elements(routes);
    select greatest(1,ceil(coalesce(b.area_hectares,0)))::integer into area_blocks
      from public.assessments aa left join public.field_boundaries b on b.id=aa.boundary_id where aa.id=c.assessment_id;
    expected := 20 * greatest(1,route_count,coalesce(area_blocks,1));
    if route_count=0 and public.expert_assessment_has_multiple_blocks(c.assessment_id)
      then raise exception 'Sync the planned sampling routes before finalizing a multi-block assessment'; end if;
    if route_count>0 and route_count*20<>expected then raise exception 'Prepare and sync every required sampling block'; end if;
    if exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id
        and e.plant_number is not null
        and (e.station_number is null or e.station_number not between 1 and 20 or e.plant_number<>1))
      then raise exception 'Link every photo to Plant 1-20 of its sampling block'; end if;
    if route_count>0 and exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id
        and e.plant_number is not null
        and not exists(select 1 from jsonb_array_elements(routes) r where r->>'block_run_id'=e.block_run_id::text))
      then raise exception 'Photo-linked sampling blocks do not match the assessment plan'; end if;
    if route_count>0 and exists(select 1 from jsonb_array_elements(routes) r
        cross join generate_series(1,20) n(plant_number)
        where not exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id
          and e.block_run_id::text=r->>'block_run_id' and e.station_number=n.plant_number and e.plant_number=1))
      then raise exception 'Request photos for every missing sampled plant; all 20 plants per block are required'; end if;
    if exists(select 1 from public.expert_plant_severity r where r.case_id=p_case_id and
        (r.outcome<>'scored' or r.davis_score is null or r.davis_score not between 0 and 9
          or (r.davis_score>0 and (r.damage_freshness is null or r.damage_freshness not in ('fresh','old_only')))))
      then raise exception 'Request clearer evidence and score every plant with assessable freshness before finalizing'; end if;
  end if;
  if exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.plant_number is not null and e.block_run_id is null and (public.expert_assessment_has_multiple_blocks(c.assessment_id) or exists(select 1 from public.evidence_files typed where typed.assessment_id=e.assessment_id and typed.station_number=e.station_number and typed.plant_number=e.plant_number and typed.block_run_id is not null))) then raise exception 'Sync all sampling block identities before finalizing'; end if;
  with plants as (select distinct block_run_id,station_number,plant_number from public.evidence_files where assessment_id=c.assessment_id and station_number is not null and plant_number is not null)
  select count(*)::integer,count(r.case_id)::integer,count(*) filter(where r.davis_score>0 and r.damage_freshness is null)::integer into total,reviewed,missing
  from plants p left join public.expert_plant_severity r on r.case_id=p_case_id and r.block_run_id is not distinct from p.block_run_id and r.station_number=p.station_number and r.plant_number=p.plant_number;
  if total=0 then raise exception 'No plant-linked photos are available'; end if;
  if reviewed<>total then raise exception 'Review every photo-linked plant before finalizing (% of % complete)',reviewed,total; end if;
  if missing>0 then raise exception 'Record damage freshness for all positive scores before finalizing'; end if;
  if is_da and (total<>expected or reviewed<>expected) then
    raise exception 'A complete DA report requires % assessable plants (% reviewed)',expected,reviewed;
  end if;
  select max(created_at) into latest_evidence from public.evidence_files where assessment_id=c.assessment_id;
  stats:=public.expert_damage_statistics_v3(p_case_id);
  select jsonb_agg(public.expert_damage_statistics_v3(p_case_id,station_number,block_run_id) || jsonb_build_object('block_sequence',sequence) order by sequence nulls last,block_run_id,station_number)
    into points from (select block_run_id,station_number,min(block_sequence) sequence from public.evidence_files where assessment_id=c.assessment_id and station_number is not null and plant_number is not null group by block_run_id,station_number) p;
  -- Per-block means count every scored plant and grade zero. The global mean
  -- remains plant-weighted; these block means are never averaged unweighted.
  select jsonb_agg(jsonb_build_object('block_run_id',b.block_run_id,'block_sequence',b.sequence,
    'scored_plants',b.scored,'mean_davis_score',b.mean,'insufficient_plants',b.insufficient,
    'reviewed_plants',b.scored+b.insufficient,'positive_plants',b.positive,'zero_damage_plants',b.zero_damage,
    'fresh_plants',b.fresh,'old_only_plants',b.old_only,'uncertain_freshness_plants',b.uncertain,'monitoring_version',2,'association_status','unique') order by b.sequence nulls last,b.block_run_id)
    into blocks from (select r.block_run_id,min(r.block_sequence) sequence,count(*) filter(where r.outcome='scored') scored,
      count(*) filter(where r.outcome='insufficient_evidence') insufficient,
      count(*) filter(where r.outcome='scored' and r.davis_score>0) positive,
      count(*) filter(where r.outcome='scored' and r.davis_score=0) zero_damage,
      count(*) filter(where r.outcome='scored' and r.davis_score>0 and r.damage_freshness='fresh') fresh,
      count(*) filter(where r.outcome='scored' and r.davis_score>0 and r.damage_freshness='old_only') old_only,
      count(*) filter(where r.outcome='scored' and r.davis_score>0 and r.damage_freshness='uncertain') uncertain,avg(r.davis_score) filter(where r.outcome='scored') mean
      from public.expert_plant_severity r where r.case_id=p_case_id and exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.block_run_id is not distinct from r.block_run_id and e.station_number=r.station_number and e.plant_number=r.plant_number)
      group by r.block_run_id) b;
  select coalesce(completed_at,submitted_at,created_at) into assessed from public.assessments where id=c.assessment_id;
  select display_name into reviewer from public.profiles where user_id=auth.uid();
  insert into public.expert_severity_summaries(case_id,reviewed_plants,scored_plants,insufficient_plants,median_davis_score,mean_davis_score,finalized_by,finalized_at,
    monitoring_version,identity_version,association_status,positive_plants,zero_damage_plants,fresh_plants,old_only_plants,uncertain_freshness_plants,unrecorded_freshness_plants,score_distribution,station_summaries,block_summaries,reviewer_name,assessed_at,reporting_version,planned_plants,latest_evidence_at)
  values(p_case_id,total,(stats->>'scored_plants')::integer,(stats->>'insufficient_plants')::integer,(stats->>'median_davis_score')::numeric,(stats->>'mean_davis_score')::numeric,auth.uid(),now(),2,2,stats->>'association_status',
    (stats->>'positive_plants')::integer,(stats->>'zero_damage_plants')::integer,(stats->>'fresh_plants')::integer,(stats->>'old_only_plants')::integer,(stats->>'uncertain_freshness_plants')::integer,0,stats->'score_distribution',coalesce(points,'[]'::jsonb),coalesce(blocks,'[]'::jsonb),reviewer,assessed,case when is_da then 3 else null end,case when is_da then expected else null end,case when is_da then latest_evidence else null end) returning * into result;
  return result;
end;
$$;

revoke all on function public.finalize_expert_severity_review(uuid) from public;
grant execute on function public.finalize_expert_severity_review(uuid) to authenticated;

create or replace function public.publish_severity_chat_message()
returns trigger language plpgsql security definer set search_path='' as $$
declare classification text;
begin
  classification := case when new.mean_davis_score is null then 'Unavailable'
    when new.mean_davis_score<=1 then 'No infestation'
    when new.mean_davis_score<=3 then 'Light infestation'
    when new.mean_davis_score<=5 then 'Moderate infestation'
    when new.mean_davis_score<=7 then 'Severe infestation' else 'Highly severe' end;
  insert into public.case_messages(case_id,sender_id,body,is_farmer_visible,created_at,expert_severity_case_id)
  values(new.case_id,new.finalized_by,'Your expert-reviewed field assessment is ready.' || E'\n' ||
    'DA severity classification: ' || classification || E'\n' ||
    case when new.mean_davis_score is null then 'Mean Davis score: unavailable.' else 'Mean Davis score: ' || new.mean_davis_score || '/9.' end || E'\n' ||
    'FAW damage incidence: ' || case when new.scored_plants>0 then round(100.0*new.positive_plants/new.scored_plants,1)::text || '% (' || new.positive_plants || '/' || new.scored_plants || ').' else 'Unavailable.' end || E'\n' ||
    'Current sampled infestation: ' || case when new.fresh_plants+new.old_only_plants+new.zero_damage_plants>0 then round(100.0*new.fresh_plants/(new.fresh_plants+new.old_only_plants+new.zero_damage_plants),1)::text || '%; based on expert-assessed fresh damage.' else 'Unavailable.' end || E'\n' ||
    'The DA classification describes leaf-damage severity, not percentage infestation or proof of pest absence. Findings refer to the assessment date. Open the review for coverage, plant findings and expert guidance.',true,new.finalized_at,new.case_id)
  on conflict(expert_severity_case_id) where expert_severity_case_id is not null do nothing;
  return new;
end;
$$;
revoke all on function public.send_case_message(uuid,uuid,text,jsonb,text,integer,integer,uuid) from public;
grant execute on function public.send_case_message(uuid,uuid,text,jsonb,text,integer,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
