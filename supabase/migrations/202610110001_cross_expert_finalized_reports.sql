-- Allow expert/admin reviewers to read other reviewers' finalized, shared
-- field results. Existing owner/assigned-expert/admin policies remain intact.
-- This migration adds SELECT access only; it changes no write/finalize RPCs.
begin;

do $migration$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
    and tablename='expert_severity_summaries'
    and policyname='expert_severity_summaries_finalized_reviewer_read') then
    create policy expert_severity_summaries_finalized_reviewer_read
    on public.expert_severity_summaries for select to authenticated
    using (
      public.is_reviewer() and finalized_at is not null and exists (
        select 1 from public.expert_cases c
        where c.id = expert_severity_summaries.case_id
          and c.evidence_photo_consent
      )
    );
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
    and tablename='expert_plant_severity'
    and policyname='expert_plant_severity_finalized_reviewer_read') then
    create policy expert_plant_severity_finalized_reviewer_read
    on public.expert_plant_severity for select to authenticated
    using (
      public.is_reviewer() and exists (
        select 1 from public.expert_cases c
        join public.expert_severity_summaries s on s.case_id = c.id
        where c.id = expert_plant_severity.case_id
          and c.evidence_photo_consent and s.finalized_at is not null
      )
    );
  end if;
end;
$migration$;

-- Chat uploads become report evidence only after they are linked to a plant
-- in evidence_files. Do not widen access to unrelated chat attachments.
create or replace function public.can_review_finalized_field_photo(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_reviewer() and exists (
    select 1 from public.evidence_files e
    join public.expert_cases c on c.assessment_id = e.assessment_id
    join public.expert_severity_summaries s on s.case_id = c.id
    join public.expert_plant_severity r on r.case_id = c.id
      and r.block_run_id is not distinct from e.block_run_id
      and r.station_number = e.station_number
      and r.plant_number = e.plant_number
    where e.storage_path = p_path
      and exists (
        select 1 from public.case_messages m
        where m.case_id = c.id and m.sender_id = c.owner_id
          and exists (
            select 1 from jsonb_array_elements(m.attachments) attachment
            where attachment->>'storage_path' = p_path
              and attachment->>'purpose' = 'field_evidence'
          )
      )
      and c.evidence_photo_consent and s.finalized_at is not null
  );
$$;
revoke all on function public.can_review_finalized_field_photo(text) from public, anon;
grant execute on function public.can_review_finalized_field_photo(text) to authenticated;

do $migration$
begin
  if not exists (select 1 from pg_policies where schemaname='storage'
    and tablename='objects'
    and policyname='case_message_finalized_field_evidence_read') then
    create policy case_message_finalized_field_evidence_read
    on storage.objects for select to authenticated
    using (bucket_id = 'case-message-images'
      and public.can_review_finalized_field_photo(name));
  end if;
end;
$migration$;

commit;
