-- Prepared against project rbzjqjfzphbrhkmonoqg on 2026-10-11.
-- EXECUTED after user confirmation on 2026-10-11; keep as an audit record, do not rerun.
-- Apply 202610110002_retire_five_station_protocol.sql first.
-- Storage files must be removed with the Storage UI/API, not SQL metadata deletes.
begin;
lock table public.assessments,public.expert_cases in share row exclusive mode;
create temporary table retired_assessment_ids(id uuid primary key) on commit drop;
insert into retired_assessment_ids values
  ('05c6b7ef-3848-4107-b102-cf503762a265'::uuid),
  ('0cb83dd8-09bd-47ee-ba8c-c4b1e514200d'::uuid),
  ('1f4e0747-d1b7-4145-9947-bee3eb6343a8'::uuid),
  ('24e6dc9b-5b66-49b3-bec8-0199027aca90'::uuid),
  ('268b0ddf-8e2b-436e-99b7-9fa067b15074'::uuid),
  ('3dad3919-5b41-4858-a58a-bb50d8c4894f'::uuid),
  ('438c3f32-a349-4606-83f7-73f6e90370d5'::uuid),
  ('44d7eb3c-fa36-45db-bc3c-6edbb93e1a18'::uuid),
  ('455aa593-8004-4e7c-baa6-7f2da366457d'::uuid),
  ('46d2ce15-4770-4fe2-85b2-fe97c2bc4c30'::uuid),
  ('601c79ee-42d6-448f-9de5-e39faa6d6f7b'::uuid),
  ('6a3f1f69-3d90-42c2-a534-7f6797a3e004'::uuid),
  ('7c050022-9da4-41f8-aea8-95b55becc5b7'::uuid),
  ('7ca01814-2de9-4456-8ed4-7bf67a6f54d1'::uuid),
  ('8613b2c9-3139-4a7e-a9da-1d1bf0fcb44c'::uuid),
  ('9cfed72d-953a-426c-9333-f20d063459f9'::uuid),
  ('b385b119-2d71-4a0e-bf49-5098049326fb'::uuid),
  ('b45ad68e-4d12-4923-a14f-77c74235386e'::uuid),
  ('b5a10cfb-f449-4405-b8bf-7589dd3c2cee'::uuid),
  ('be576502-dc8a-4ada-a841-eff095783d50'::uuid),
  ('cfe5a75a-f015-4c63-9cf3-89855755438b'::uuid),
  ('d3216e24-c767-4129-aeb7-96c76035eafa'::uuid),
  ('d9c8ecc6-eaba-4779-ab26-83b99f00f4d4'::uuid),
  ('e4d7cd08-9bd3-426f-976f-c65a951379fd'::uuid),
  ('e74fd4b8-79b3-44f7-a442-8a2d87a0ca0b'::uuid),
  ('f32760d9-cac4-49dd-9a21-c0d81141623d'::uuid),
  ('f9a82e17-5391-4428-9bef-7c70ab295994'::uuid),
  ('ff8957aa-7d77-47e2-9e52-adab7555d4c1'::uuid);
create temporary table retired_case_ids on commit drop as
 select id from public.expert_cases where assessment_id in(select id from retired_assessment_ids);
create temporary table preserved_da_state on commit drop as
 select (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.id)::text,'[]'))
         from public.assessments a where a.id not in(select id from retired_assessment_ids)) as assessments,
        (select md5(coalesce(jsonb_agg(to_jsonb(s) order by s.case_id)::text,'[]'))
         from public.expert_severity_summaries s where s.case_id not in(select id from retired_case_ids)) as summaries;
do $$
begin
 if (select count(*) from public.assessments where id in(select id from retired_assessment_ids))<>28
 or exists(select 1 from public.assessments a join retired_assessment_ids t on t.id=a.id
           where a.protocol_version<>'wormwise-maize-faw-2026.1-draft'
           or coalesce(a.result_snapshot->>'scouting_pattern','') not in('w','ladder'))
 or (select count(*) from retired_case_ids)<>9 then
   raise exception 'Legacy cleanup inventory changed; refresh the read-only inventory before deletion';
 end if;
 if exists(select 1 from public.case_messages m
           where m.case_id not in(select id from retired_case_ids)
           and m.request_message_id in(select id from public.case_messages where case_id in(select id from retired_case_ids)))
 or exists(select 1 from public.evidence_files e
           where e.assessment_id not in(select id from retired_assessment_ids)
           and e.source_message_id in(select id from public.case_messages where case_id in(select id from retired_case_ids))) then
   raise exception 'A current record refers to a retired message; review that link before deletion';
 end if;
end;
$$;
-- Remove only retired summaries first, allowing their immutable ratings and CV
-- feedback to cascade through the existing guards without disabling triggers.
delete from public.expert_severity_summaries where case_id in(select id from retired_case_ids);
delete from public.evidence_files where assessment_id in(select id from retired_assessment_ids);
delete from public.dashboard_notifications where case_id in(select id from retired_case_ids);
delete from public.expert_cases where id in(select id from retired_case_ids);
delete from public.assessments where id in(select id from retired_assessment_ids);
alter table public.assessments validate constraint assessments_no_retired_five_station_protocol;
do $$
begin
 if exists(select 1 from public.assessments where id in(select id from retired_assessment_ids)) then
   raise exception 'Retired assessments remain';
 end if;
 if (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.id)::text,'[]')) from public.assessments a)
      is distinct from (select assessments from preserved_da_state)
 or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by s.case_id)::text,'[]')) from public.expert_severity_summaries s)
      is distinct from (select summaries from preserved_da_state) then
   raise exception 'Current assessment or finalized review changed; cleanup rolled back';
 end if;
end;
$$;
commit;
select jsonb_build_object(
 'Retired W/ladder assessments remaining',(select count(*) from public.assessments where protocol_version='wormwise-maize-faw-2026.1-draft'),
 'Current DA assessments retained',(select count(*) from public.assessments where protocol_version='wormwise-da-scattered-20-v1'),
 'Current submitted DA cases retained',(select count(*) from public.expert_cases),
 'Current finalized reviews retained',(select count(*) from public.expert_severity_summaries),
 'Retired protocol blocked',(select convalidated from pg_constraint where conrelid='public.assessments'::regclass and conname='assessments_no_retired_five_station_protocol')
) as retired_scouting_cleanup_verified;

