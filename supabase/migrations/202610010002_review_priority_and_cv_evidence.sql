-- Apply after the dashboard's expert-plant-severity and finalized-summary
-- migrations (202609250001 and 202609250002).
begin;

-- Only photo-consented evidence carries image-specific CV metadata. Legacy
-- evidence remains NULL: a merged plant result is not an image overlay.
alter table public.evidence_files add column cv_analysis jsonb;
alter table public.evidence_files add constraint evidence_cv_identity check (
  cv_analysis is null or (
    jsonb_typeof(cv_analysis) = 'object'
    and (cv_analysis->>'schema_version' = '1') is true
    and (cv_analysis->>'evidence_id' = id::text) is true
    and (cv_analysis->>'sha256' = sha256) is true
    and length(coalesce(sha256, '')) > 0
    and octet_length(cv_analysis::text) <= 65536
  )
);

alter table public.expert_cases
  add column priority_requested boolean not null default false,
  add column priority_reason text not null default '',
  add column priority_by uuid references auth.users(id),
  add column priority_at timestamptz,
  add constraint expert_case_priority_reason check (
    length(priority_reason) <= 300 and
    ((priority_requested and length(trim(priority_reason)) > 0) or
     (not priority_requested and priority_reason = ''))
  );

create function public.guard_expert_case_priority()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.priority_requested or new.priority_by is not null or new.priority_at is not null then
      raise exception 'New cases cannot supply a reviewer priority';
    end if;
    return new;
  end if;
  if new.priority_requested is distinct from old.priority_requested
     or new.priority_reason is distinct from old.priority_reason
     or new.priority_by is distinct from old.priority_by
     or new.priority_at is distinct from old.priority_at then
    if old.status = 'closed' or not exists (
      select 1 from public.profiles p where p.user_id = auth.uid()
      and (p.account_kind = 'admin' or
        (p.account_kind = 'expert' and old.claimed_by = auth.uid()))
    ) then raise exception 'Admin or assigned expert access to an open case is required'; end if;
    new.priority_by := case when new.priority_requested then auth.uid() else null end;
    new.priority_at := case when new.priority_requested then now() else null end;
  end if;
  return new;
end;
$$;
create trigger expert_case_priority_guard before insert or update on public.expert_cases
for each row execute function public.guard_expert_case_priority();

create function public.set_expert_case_priority(p_case_id uuid, p_requested boolean, p_reason text default '')
returns public.expert_cases language plpgsql security definer set search_path = '' as $$
declare v_case public.expert_cases;
begin
  select * into v_case from public.expert_cases where id = p_case_id for update;
  if v_case.id is null or v_case.status = 'closed' or p_requested is null or not exists (
    select 1 from public.profiles p where p.user_id = auth.uid()
    and (p.account_kind = 'admin' or (p.account_kind = 'expert' and v_case.claimed_by = auth.uid()))
  ) then raise exception 'Admin or assigned expert access to an open case is required'; end if;
  update public.expert_cases set priority_requested = p_requested,
    priority_reason = case when p_requested then trim(coalesce(p_reason,'')) else '' end,
    priority_by = case when p_requested then auth.uid() else null end,
    priority_at = case when p_requested then now() else null end
  where id = p_case_id returning * into v_case;
  return v_case;
end;
$$;
revoke all on function public.set_expert_case_priority(uuid,boolean,text) from public;
grant execute on function public.set_expert_case_priority(uuid,boolean,text) to authenticated;

-- Return only the measurements needed by the queue, without routes or GPS.
create function public.get_review_queue_samples(p_assessment_ids uuid[])
returns table(id uuid, growth_stage text, result_snapshot jsonb)
language sql stable security definer set search_path = '' as $$
  select a.id, a.growth_stage::text, jsonb_build_object(
    'measurement_basis', a.result_snapshot->'measurement_basis',
    'sampling_summary', a.result_snapshot->'sampling_summary',
    'metrics', a.result_snapshot->'metrics',
    'growth_stage_uncertain', coalesce(a.result_snapshot->'growth_stage_uncertain',
      to_jsonb(coalesce(a.result_snapshot->'warnings' @> '["The recorded growth stage was marked uncertain."]'::jsonb, false)))
  ) from public.assessments a where a.id = any(p_assessment_ids)
    and public.is_reviewer() and public.can_review_assessment(a.id);
$$;
revoke all on function public.get_review_queue_samples(uuid[]) from public;
grant execute on function public.get_review_queue_samples(uuid[]) to authenticated;

create table public.expert_cv_feedback (
  case_id uuid not null references public.expert_cases(id) on delete cascade,
  evidence_id uuid not null references public.evidence_files(id) on delete cascade,
  outcome text not null check (outcome in ('supported','not_supported','uncertain')),
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default now(),
  primary key (case_id, evidence_id)
);
alter table public.expert_cv_feedback enable row level security;
create policy expert_cv_feedback_read on public.expert_cv_feedback for select to authenticated using (
  exists (select 1 from public.expert_cases c where c.id = case_id and c.evidence_photo_consent
    and (c.owner_id = auth.uid() or (public.is_reviewer() and
      (c.claimed_by = auth.uid() or exists (select 1 from public.profiles p
        where p.user_id = auth.uid() and p.account_kind = 'admin')))))
);
grant select on public.expert_cv_feedback to authenticated;
create trigger expert_cv_feedback_finalized_guard before insert or update or delete on public.expert_cv_feedback
for each row execute function public.prevent_finalized_severity_changes();

create function public.save_expert_cv_feedback(p_case_id uuid, p_evidence_id uuid, p_outcome text)
returns public.expert_cv_feedback language plpgsql security definer set search_path = '' as $$
declare v_case public.expert_cases; v_result public.expert_cv_feedback;
begin
  select * into v_case from public.expert_cases where id = p_case_id for update;
  if v_case.id is null or v_case.claimed_by is distinct from auth.uid()
     or v_case.status = 'closed' or not v_case.evidence_photo_consent
     or not exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.account_kind = 'expert') then
    raise exception 'Assigned expert access to shared evidence is required';
  end if;
  if p_outcome is null or p_outcome not in ('supported','not_supported','uncertain') then
    raise exception 'Choose a valid model feedback outcome';
  end if;
  if not exists (select 1 from public.evidence_files e where e.id = p_evidence_id
    and e.assessment_id = v_case.assessment_id and e.cv_analysis->>'detector_used' = 'true'
    and e.cv_analysis->'result'->>'classifierStage' = 'overlay_complete'
    and case when jsonb_typeof(e.cv_analysis->'result'->'detectionBoxes') = 'array'
      then jsonb_array_length(e.cv_analysis->'result'->'detectionBoxes') > 0 else false end) then
    raise exception 'Saved image-specific detector suggestions are required';
  end if;
  insert into public.expert_cv_feedback(case_id,evidence_id,outcome,reviewed_by,reviewed_at)
  values(p_case_id,p_evidence_id,p_outcome,auth.uid(),now())
  on conflict(case_id,evidence_id) do update set outcome=excluded.outcome,
    reviewed_by=excluded.reviewed_by, reviewed_at=excluded.reviewed_at returning * into v_result;
  return v_result;
end;
$$;
revoke all on function public.save_expert_cv_feedback(uuid,uuid,text) from public;
grant execute on function public.save_expert_cv_feedback(uuid,uuid,text) to authenticated;
notify pgrst, 'reload schema';
commit;
