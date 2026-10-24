-- Atomic farmer submission of a completed assessment for expert review.
-- Evidence objects/metadata are uploaded before this function is called.

create or replace function public.submit_assessment_for_expert_review(
  p_assessment_id uuid,
  p_farmer_display_name text,
  p_field_name text,
  p_barangay text,
  p_municipality text,
  p_province text,
  p_location_consent boolean default false,
  p_evidence_consent boolean default false,
  p_farmer_question text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner uuid := (select auth.uid());
  v_case_id uuid;
begin
  if v_owner is null then
    raise exception 'Authentication is required';
  end if;
  if char_length(trim(p_farmer_display_name)) not between 2 and 120 then
    raise exception 'Farmer name must contain 2 to 120 characters';
  end if;
  if char_length(trim(p_field_name)) not between 1 and 160 then
    raise exception 'Field name is required';
  end if;
  if trim(coalesce(p_barangay, '')) = '' then
    raise exception 'Barangay is required';
  end if;

  select id into v_case_id
  from public.expert_cases
  where assessment_id = p_assessment_id and owner_id = v_owner;
  if v_case_id is not null then
    return v_case_id;
  end if;

  update public.assessments
  set status = 'submitted', submitted_at = now()
  where id = p_assessment_id
    and owner_id = v_owner
    and status = 'completed'
    and completed_at is not null
    and result_snapshot is not null;
  if not found then
    raise exception 'Only a synchronized, completed assessment can be submitted';
  end if;

  insert into public.expert_cases(
    owner_id, assessment_id, farmer_display_name, field_name_snapshot,
    barangay_snapshot, municipality_snapshot, province_snapshot,
    approximate_location_consent, evidence_photo_consent, farmer_question
  ) values (
    v_owner, p_assessment_id, trim(p_farmer_display_name), trim(p_field_name),
    trim(p_barangay), trim(p_municipality), trim(p_province),
    p_location_consent, p_evidence_consent, nullif(trim(p_farmer_question), '')
  ) returning id into v_case_id;

  return v_case_id;
end;
$$;

revoke all on function public.submit_assessment_for_expert_review(
  uuid, text, text, text, text, text, boolean, boolean, text
) from public;
grant execute on function public.submit_assessment_for_expert_review(
  uuid, text, text, text, text, text, boolean, boolean, text
) to authenticated;
