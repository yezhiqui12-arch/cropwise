begin;

-- Internal photo-review notes, independent of published Davis ratings.
create table public.expert_evidence_notes (
  case_id uuid not null references public.expert_cases(id) on delete cascade,
  evidence_id uuid not null references public.evidence_files(id) on delete cascade,
  note text not null default '' check (char_length(note) <= 1000),
  revision integer not null default 1 check (revision > 0),
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default now(),
  primary key (case_id, evidence_id)
);
alter table public.expert_evidence_notes enable row level security;
create policy expert_evidence_notes_read on public.expert_evidence_notes
for select to authenticated using (
  public.is_reviewer() and exists (
    select 1 from public.expert_cases c where c.id = case_id and c.evidence_photo_consent
  )
);
grant select on public.expert_evidence_notes to authenticated;

create function public.save_expert_evidence_note(
  p_case_id uuid, p_evidence_id uuid, p_note text, p_expected_revision integer default 0
)
returns public.expert_evidence_notes
language plpgsql security definer set search_path = '' as $$
declare
  v_case public.expert_cases;
  v_previous public.expert_evidence_notes;
  v_result public.expert_evidence_notes;
  v_note text;
begin
  -- Serializes note saves with case closure, assignment and other note saves.
  select * into v_case from public.expert_cases where id = p_case_id for update;
  if v_case.id is null or v_case.status = 'closed' or not v_case.evidence_photo_consent
     or not exists (select 1 from public.profiles p where p.user_id = auth.uid()
       and (p.account_kind = 'admin' or
         (p.account_kind = 'expert' and v_case.claimed_by = auth.uid()))) then
    raise exception 'Admin or assigned expert access to an open case with shared evidence is required';
  end if;
  if not exists (select 1 from public.evidence_files e where e.id = p_evidence_id
    and e.assessment_id = v_case.assessment_id) then
    raise exception 'The photo must belong to this submitted assessment';
  end if;
  v_note := coalesce(p_note, '');
  if char_length(v_note) > 1000 or p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Evidence notes must contain at most 1000 characters';
  end if;
  select * into v_previous from public.expert_evidence_notes
    where case_id = p_case_id and evidence_id = p_evidence_id;
  if coalesce(v_previous.revision, 0) <> p_expected_revision then
    raise exception 'This note changed since you opened it. Refresh the case before saving again. Your draft is preserved.';
  end if;
  insert into public.expert_evidence_notes(case_id,evidence_id,note,revision,reviewed_by,reviewed_at)
  values(p_case_id,p_evidence_id,v_note,1,auth.uid(),now())
  on conflict(case_id,evidence_id) do update set note=excluded.note,
    revision=expert_evidence_notes.revision+1, reviewed_by=excluded.reviewed_by, reviewed_at=excluded.reviewed_at
  returning * into v_result;
  return v_result;
end;
$$;
revoke all on function public.save_expert_evidence_note(uuid,uuid,text,integer) from public;
grant execute on function public.save_expert_evidence_note(uuid,uuid,text,integer) to authenticated;
notify pgrst, 'reload schema';
commit;
