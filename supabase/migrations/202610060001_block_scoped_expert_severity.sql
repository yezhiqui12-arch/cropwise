-- Stable sampling-block identity for evidence and expert ratings.
-- Apply after 202610010004_expert_damage_freshness.sql. Historical finalized
-- grades are never reassigned, duplicated, deleted or unlocked.
begin;

alter table public.evidence_files
  add column block_run_id uuid,
  add column block_sequence integer check (block_sequence > 0);
alter table public.expert_plant_severity
  add column block_run_id uuid,
  add column block_sequence integer check (block_sequence > 0);
alter table public.expert_severity_summaries
  add column identity_version integer not null default 1,
  add column mean_davis_score numeric(8,4) check (mean_davis_score between 0 and 9),
  add column block_summaries jsonb;

-- Only unresolved drafts with exactly one possible block are backfilled.
-- Repeated point numbers across blocks are deliberately left unresolved.
with candidates as (
  select assessment_id, station_number, block_run_id from public.assessment_stations
  where block_run_id is not null
  union
  select a.id, (p->>'station_number')::integer, (p->>'block_run_id')::uuid
  from public.assessments a
  cross join lateral jsonb_array_elements(coalesce(a.result_snapshot->'automatic_damage_screen'->'stations','[]'::jsonb)) p
  where p->>'block_run_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and p->>'station_number' ~ '^[1-9][0-9]*$'
), unique_points as (
  select assessment_id,station_number,min(block_run_id::text)::uuid block_id
  from candidates group by assessment_id,station_number having count(distinct block_run_id)=1
)
update public.evidence_files e set block_run_id=p.block_id
from unique_points p where p.assessment_id=e.assessment_id and p.station_number=e.station_number
  and not exists(select 1 from public.expert_cases c join public.expert_severity_summaries s on s.case_id=c.id where c.assessment_id=e.assessment_id);

with unique_plants as (
  select c.id case_id,e.station_number,e.plant_number,min(e.block_run_id::text)::uuid block_id
  from public.evidence_files e join public.expert_cases c on c.assessment_id=e.assessment_id
  group by c.id,e.station_number,e.plant_number
  having count(*) filter(where e.block_run_id is null)=0 and count(distinct e.block_run_id)=1
)
update public.expert_plant_severity r set block_run_id=p.block_id
from unique_plants p where p.case_id=r.case_id and p.station_number=r.station_number and p.plant_number=r.plant_number
  and not exists(select 1 from public.expert_severity_summaries s where s.case_id=r.case_id);

alter table public.expert_plant_severity drop constraint expert_plant_severity_pkey;
alter table public.expert_plant_severity add column plant_key text generated always as
  (coalesce(block_run_id::text,'legacy') || ':' || station_number::text || ':' || plant_number::text) stored;
alter table public.expert_plant_severity add primary key(case_id,plant_key);
create index evidence_files_block_plant_idx on public.evidence_files(assessment_id,block_run_id,station_number,plant_number);

create or replace function public.expert_assessment_has_multiple_blocks(p_assessment_id uuid)
returns boolean language sql stable set search_path='' as $$
  select count(distinct block_id)>1 from (
    select st.block_run_id::text block_id from public.assessment_stations st where st.assessment_id=p_assessment_id
    union all
    select p->>'block_run_id' from public.assessments a
      cross join lateral jsonb_array_elements(coalesce(a.result_snapshot->'sampling_routes','[]'::jsonb)) p where a.id=p_assessment_id
    union all
    select p->>'block_run_id' from public.assessments a
      cross join lateral jsonb_array_elements(coalesce(a.result_snapshot->'automatic_damage_screen'->'stations','[]'::jsonb)) p where a.id=p_assessment_id
    union all
    select e.block_run_id::text from public.evidence_files e where e.assessment_id=p_assessment_id
    union all
    select 'additional-planned-block' from public.assessments a where a.id=p_assessment_id
      and (a.protocol_version='wormwise-da-scattered-20-v1' or a.result_snapshot->>'scouting_pattern'='da_scattered_20')
      and a.result_snapshot->'sampling_summary'->>'planned_sample_count' ~ '^[0-9]+$'
      and (a.result_snapshot->'sampling_summary'->>'planned_sample_count')::integer>=40
      and (a.result_snapshot->'sampling_summary'->>'planned_sample_count')::integer%20=0
    union all
    select 'first-planned-block' from public.assessments a where a.id=p_assessment_id
      and (a.protocol_version='wormwise-da-scattered-20-v1' or a.result_snapshot->>'scouting_pattern'='da_scattered_20')
      and a.result_snapshot->'sampling_summary'->>'planned_sample_count' ~ '^[0-9]+$'
      and (a.result_snapshot->'sampling_summary'->>'planned_sample_count')::integer>=40
      and (a.result_snapshot->'sampling_summary'->>'planned_sample_count')::integer%20=0
  ) blocks where block_id is not null;
$$;
revoke all on function public.expert_assessment_has_multiple_blocks(uuid) from public;

-- Serialize evidence identity changes with expert saving/finalization. Published
-- evidence retains its original linkage, including unresolved historical rows.
create or replace function public.guard_expert_evidence_identity()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform c.id from public.expert_cases c where c.assessment_id=new.assessment_id order by c.id for update;
  if tg_op='UPDATE' and (new.assessment_id is distinct from old.assessment_id or
      new.owner_id is distinct from old.owner_id or new.station_number is distinct from old.station_number or new.plant_number is distinct from old.plant_number) then
    raise exception 'Evidence plant identity cannot be retargeted';
  end if;
  if (tg_op='INSERT' or new.block_run_id is distinct from old.block_run_id or new.block_sequence is distinct from old.block_sequence)
    and exists(select 1 from public.expert_cases c join public.expert_severity_summaries s on s.case_id=c.id where c.assessment_id=new.assessment_id) then
    raise exception 'Finalized evidence identity cannot be changed';
  end if;
  if tg_op='UPDATE' and old.block_run_id is not null and new.block_run_id is distinct from old.block_run_id then
    raise exception 'Evidence sampling block cannot be retargeted';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_expert_evidence_identity() from public;
create trigger expert_evidence_identity_guard before insert or update on public.evidence_files for each row execute function public.guard_expert_evidence_identity();

-- Retry-safe metadata repair for photos already uploaded by older mobile builds.
-- The owner can fill an unset block identity, never retarget an existing one.
create or replace function public.sync_evidence_block_identity(p_evidence_id uuid,p_block_run_id uuid,p_block_sequence integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare e public.evidence_files%rowtype;
begin
  select * into e from public.evidence_files where id=p_evidence_id and owner_id=auth.uid();
  if e.id is null then return false; end if;
  perform c.id from public.expert_cases c where c.assessment_id=e.assessment_id order by c.id for update;
  if exists(select 1 from public.expert_cases c join public.expert_severity_summaries s on s.case_id=c.id where c.assessment_id=e.assessment_id) then return false; end if;
  if p_block_run_id is null or p_block_sequence is null or p_block_sequence<1 then raise exception 'A sampling block is required'; end if;
  if e.block_run_id is not null and e.block_run_id<>p_block_run_id then raise exception 'The photo belongs to another sampling block'; end if;
  update public.evidence_files set block_run_id=p_block_run_id,block_sequence=p_block_sequence where id=e.id;
  -- A unique draft may acquire metadata without changing its saved judgment.
  -- Ambiguous drafts are retained unassigned and must be scored separately.
  update public.expert_plant_severity r set block_run_id=p_block_run_id,block_sequence=p_block_sequence
    from public.expert_cases c where c.id=r.case_id and c.assessment_id=e.assessment_id and r.block_run_id is null
      and r.station_number=e.station_number and r.plant_number=e.plant_number
      and not exists(select 1 from public.evidence_files f where f.assessment_id=e.assessment_id and f.station_number=e.station_number and f.plant_number=e.plant_number and f.block_run_id is distinct from p_block_run_id)
      and not exists(select 1 from public.expert_plant_severity typed where typed.case_id=r.case_id and typed.block_run_id=p_block_run_id and typed.station_number=r.station_number and typed.plant_number=r.plant_number);
  return true;
end;
$$;
revoke all on function public.sync_evidence_block_identity(uuid,uuid,integer) from public;
grant execute on function public.sync_evidence_block_identity(uuid,uuid,integer) to authenticated;

create or replace function public.save_expert_plant_severity_v3(
  p_case_id uuid,p_station_number integer,p_plant_number integer,p_outcome text,
  p_davis_score integer,p_note text default '',p_damage_freshness text default null,p_block_run_id uuid default null
) returns public.expert_plant_severity language plpgsql security definer set search_path='' as $$
declare c public.expert_cases%rowtype; result public.expert_plant_severity%rowtype; sequence integer;
begin
  select * into c from public.expert_cases where id=p_case_id for update;
  if c.id is null or c.claimed_by is distinct from auth.uid() or c.status='closed' or not c.evidence_photo_consent
    or not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.account_kind='expert') then raise exception 'Assigned expert access to shared evidence is required'; end if;
  if exists(select 1 from public.expert_severity_summaries s where s.case_id=p_case_id) then raise exception 'Finalized severity ratings cannot be changed'; end if;
  if p_station_number is null or p_station_number<1 or p_plant_number is null or p_plant_number<1
    or not exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.station_number=p_station_number and e.plant_number=p_plant_number and e.block_run_id is not distinct from p_block_run_id) then raise exception 'Plant-linked evidence in this sampling block is required'; end if;
  if p_block_run_id is null and (public.expert_assessment_has_multiple_blocks(c.assessment_id) or exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.station_number=p_station_number and e.plant_number=p_plant_number and e.block_run_id is not null)) then raise exception 'Sync sampling block identities before reviewing this plant'; end if;
  if p_outcome is null or p_outcome not in ('scored','insufficient_evidence')
    or (p_outcome='scored' and (p_davis_score is null or p_davis_score not between 0 and 9))
    or (p_outcome='insufficient_evidence' and p_davis_score is not null) or length(coalesce(p_note,''))>1000 then raise exception 'Invalid severity rating'; end if;
  if p_outcome='scored' and p_davis_score>0 then
    if p_damage_freshness is null or p_damage_freshness not in ('fresh','old_only','uncertain') then raise exception 'Choose damage freshness for a positive score'; end if;
  elsif p_damage_freshness is not null then raise exception 'Freshness applies only to a positive damage score'; end if;
  select min(e.block_sequence) into sequence from public.evidence_files e where e.assessment_id=c.assessment_id and e.station_number=p_station_number and e.plant_number=p_plant_number and e.block_run_id is not distinct from p_block_run_id;
  insert into public.expert_plant_severity(case_id,block_run_id,block_sequence,station_number,plant_number,outcome,davis_score,note,rated_by,rated_at,damage_freshness)
  values(p_case_id,p_block_run_id,sequence,p_station_number,p_plant_number,p_outcome,p_davis_score,coalesce(p_note,''),auth.uid(),now(),p_damage_freshness)
  on conflict(case_id,plant_key) do update set outcome=excluded.outcome,davis_score=excluded.davis_score,note=excluded.note,rated_by=excluded.rated_by,rated_at=now(),damage_freshness=excluded.damage_freshness,block_sequence=excluded.block_sequence returning * into result;
  return result;
end;
$$;
revoke all on function public.save_expert_plant_severity_v3(uuid,integer,integer,text,integer,text,text,uuid) from public;
grant execute on function public.save_expert_plant_severity_v3(uuid,integer,integer,text,integer,text,text,uuid) to authenticated;

-- Old clients can save only when their point/plant identifies exactly one block.
create or replace function public.save_expert_plant_severity_v2(p_case_id uuid,p_station_number integer,p_plant_number integer,p_outcome text,p_davis_score integer,p_note text default '',p_damage_freshness text default null)
returns public.expert_plant_severity language plpgsql security definer set search_path='' as $$
declare block_id uuid; blocks integer;
begin
  perform c.id from public.expert_cases c where c.id=p_case_id for update;
  select count(distinct coalesce(e.block_run_id::text,'legacy')),min(e.block_run_id::text)::uuid into blocks,block_id
    from public.evidence_files e join public.expert_cases c on c.assessment_id=e.assessment_id where c.id=p_case_id and e.station_number=p_station_number and e.plant_number=p_plant_number;
  if blocks<>1 then raise exception 'This plant number occurs in multiple sampling blocks; update the dashboard'; end if;
  return public.save_expert_plant_severity_v3(p_case_id,p_station_number,p_plant_number,p_outcome,p_davis_score,p_note,p_damage_freshness,block_id);
end;
$$;

create or replace function public.expert_damage_statistics_v3(p_case_id uuid,p_station_number integer default null,p_block_run_id uuid default null)
returns jsonb language sql stable set search_path='' as $$
  with ratings as (
    select r.* from public.expert_plant_severity r join public.expert_cases c on c.id=r.case_id
    where r.case_id=p_case_id and (p_station_number is null or (r.station_number=p_station_number and r.block_run_id is not distinct from p_block_run_id))
      and exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.station_number=r.station_number and e.plant_number=r.plant_number and e.block_run_id is not distinct from r.block_run_id)
  ), stats as (
    select count(*)::integer reviewed,count(*) filter(where outcome='scored')::integer scored,
      count(*) filter(where outcome='insufficient_evidence')::integer insufficient,
      count(*) filter(where davis_score>0)::integer positive,count(*) filter(where davis_score=0)::integer zero_damage,
      count(*) filter(where damage_freshness='fresh')::integer fresh,count(*) filter(where damage_freshness='old_only')::integer old_only,
      count(*) filter(where damage_freshness='uncertain')::integer uncertain,count(*) filter(where davis_score>0 and damage_freshness is null)::integer unrecorded,
      (percentile_cont(.5) within group(order by davis_score) filter(where outcome='scored'))::numeric(4,2) median,
      avg(davis_score) filter(where outcome='scored') mean from ratings
  ), histogram as (
    select jsonb_agg(n order by grade) bins from (select g.grade,count(r.davis_score)::integer n from pg_catalog.generate_series(0,9) g(grade) left join ratings r on r.outcome='scored' and r.davis_score=g.grade group by g.grade) counts
  ) select jsonb_build_object('station_number',p_station_number,'block_run_id',p_block_run_id,'identity_version',2,'monitoring_version',2,
    'association_status',case when exists(select 1 from public.expert_cases c join public.evidence_files e on e.assessment_id=c.assessment_id where c.id=p_case_id and e.plant_number is not null and e.block_run_id is null and public.expert_assessment_has_multiple_blocks(c.assessment_id)) then 'ambiguous' else 'unique' end,
    'reviewed_plants',reviewed,'scored_plants',scored,'insufficient_plants',insufficient,'positive_plants',positive,'zero_damage_plants',zero_damage,
    'fresh_plants',fresh,'old_only_plants',old_only,'uncertain_freshness_plants',uncertain,'unrecorded_freshness_plants',unrecorded,
    'median_davis_score',median,'mean_davis_score',mean,'score_distribution',bins) from stats cross join histogram;
$$;
revoke all on function public.expert_damage_statistics_v3(uuid,integer,uuid) from public;

create or replace function public.finalize_expert_severity_review(p_case_id uuid)
returns public.expert_severity_summaries language plpgsql security definer set search_path='' as $$
declare c public.expert_cases%rowtype; result public.expert_severity_summaries%rowtype;
  total integer; reviewed integer; missing integer; stats jsonb; points jsonb; blocks jsonb; assessed timestamptz; reviewer text;
begin
  select * into c from public.expert_cases where id=p_case_id for update;
  if c.id is null or c.claimed_by is distinct from auth.uid() or c.status='closed' or not c.evidence_photo_consent
    or not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.account_kind='expert') then raise exception 'Assigned expert access to an open case with shared evidence is required'; end if;
  select * into result from public.expert_severity_summaries where case_id=p_case_id;
  if result.case_id is not null then return result; end if;
  if exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.plant_number is not null and e.block_run_id is null and (public.expert_assessment_has_multiple_blocks(c.assessment_id) or exists(select 1 from public.evidence_files typed where typed.assessment_id=e.assessment_id and typed.station_number=e.station_number and typed.plant_number=e.plant_number and typed.block_run_id is not null))) then raise exception 'Sync all sampling block identities before finalizing'; end if;
  with plants as (select distinct block_run_id,station_number,plant_number from public.evidence_files where assessment_id=c.assessment_id and station_number is not null and plant_number is not null)
  select count(*)::integer,count(r.case_id)::integer,count(*) filter(where r.davis_score>0 and r.damage_freshness is null)::integer into total,reviewed,missing
  from plants p left join public.expert_plant_severity r on r.case_id=p_case_id and r.block_run_id is not distinct from p.block_run_id and r.station_number=p.station_number and r.plant_number=p.plant_number;
  if total=0 then raise exception 'No plant-linked photos are available'; end if;
  if reviewed<>total then raise exception 'Review every photo-linked plant before finalizing (% of % complete)',reviewed,total; end if;
  if missing>0 then raise exception 'Record damage freshness for all positive scores before finalizing'; end if;
  stats:=public.expert_damage_statistics_v3(p_case_id);
  select jsonb_agg(public.expert_damage_statistics_v3(p_case_id,station_number,block_run_id) || jsonb_build_object('block_sequence',sequence) order by sequence nulls last,block_run_id,station_number)
    into points from (select block_run_id,station_number,min(block_sequence) sequence from public.evidence_files where assessment_id=c.assessment_id and station_number is not null and plant_number is not null group by block_run_id,station_number) p;
  -- Per-block means count every scored plant and grade zero. The global mean
  -- remains plant-weighted; these block means are never averaged unweighted.
  select jsonb_agg(jsonb_build_object('block_run_id',b.block_run_id,'block_sequence',b.sequence,
    'scored_plants',b.scored,'mean_davis_score',b.mean,'insufficient_plants',b.insufficient) order by b.sequence nulls last,b.block_run_id)
    into blocks from (select r.block_run_id,min(r.block_sequence) sequence,count(*) filter(where r.outcome='scored') scored,
      count(*) filter(where r.outcome='insufficient_evidence') insufficient,avg(r.davis_score) filter(where r.outcome='scored') mean
      from public.expert_plant_severity r where r.case_id=p_case_id and exists(select 1 from public.evidence_files e where e.assessment_id=c.assessment_id and e.block_run_id is not distinct from r.block_run_id and e.station_number=r.station_number and e.plant_number=r.plant_number)
      group by r.block_run_id) b;
  select coalesce(completed_at,submitted_at,created_at) into assessed from public.assessments where id=c.assessment_id;
  select display_name into reviewer from public.profiles where user_id=auth.uid();
  insert into public.expert_severity_summaries(case_id,reviewed_plants,scored_plants,insufficient_plants,median_davis_score,mean_davis_score,finalized_by,finalized_at,
    monitoring_version,identity_version,association_status,positive_plants,zero_damage_plants,fresh_plants,old_only_plants,uncertain_freshness_plants,unrecorded_freshness_plants,score_distribution,station_summaries,block_summaries,reviewer_name,assessed_at)
  values(p_case_id,total,(stats->>'scored_plants')::integer,(stats->>'insufficient_plants')::integer,(stats->>'median_davis_score')::numeric,(stats->>'mean_davis_score')::numeric,auth.uid(),now(),2,2,stats->>'association_status',
    (stats->>'positive_plants')::integer,(stats->>'zero_damage_plants')::integer,(stats->>'fresh_plants')::integer,(stats->>'old_only_plants')::integer,(stats->>'uncertain_freshness_plants')::integer,0,stats->'score_distribution',coalesce(points,'[]'::jsonb),coalesce(blocks,'[]'::jsonb),reviewer,assessed) returning * into result;
  return result;
end;
$$;

create or replace function public.publish_severity_chat_message()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.case_messages(case_id,sender_id,body,is_farmer_visible,created_at,expert_severity_case_id)
  values(new.case_id,new.finalized_by,'Your expert-reviewed FAW damage severity is ready.' || E'\n' ||
    case when new.mean_davis_score is null then 'No plants could be scored from the submitted photos.' else 'Mean Davis score: ' || new.mean_davis_score || '/9.' end || E'\n' ||
    new.scored_plants || ' scored; ' || new.insufficient_plants || ' insufficient evidence. Open the review to see the plant scores and photos.',true,new.finalized_at,new.case_id)
  on conflict(expert_severity_case_id) where expert_severity_case_id is not null do nothing;
  return new;
end;
$$;

notify pgrst,'reload schema';
commit;
