-- Remove the fields -> assessments -> fields RLS cycle.
-- SECURITY DEFINER helpers execute as the migration owner and therefore do
-- not recursively evaluate the caller-facing table policies.

create or replace function public.owns_field(target_field uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.fields f
    where f.id = target_field and f.owner_id = (select auth.uid())
  );
$$;

create or replace function public.can_review_field(target_field uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_reviewer() and exists (
    select 1
    from public.assessments a
    join public.expert_cases c on c.assessment_id = a.id
    where a.field_id = target_field and c.approximate_location_consent
  );
$$;

create or replace function public.can_review_boundary(target_boundary uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_reviewer() and exists (
    select 1
    from public.expert_cases c
    join public.assessments a on a.id = c.assessment_id
    where a.boundary_id = target_boundary and c.approximate_location_consent
  );
$$;

revoke all on function public.owns_field(uuid) from public;
revoke all on function public.can_review_field(uuid) from public;
revoke all on function public.can_review_boundary(uuid) from public;
grant execute on function public.owns_field(uuid) to authenticated;
grant execute on function public.can_review_field(uuid) to authenticated;
grant execute on function public.can_review_boundary(uuid) to authenticated;

drop policy if exists fields_owner_select on public.fields;
create policy fields_owner_select on public.fields for select to authenticated
  using (
    owner_id = (select auth.uid())
    or public.can_review_field(id)
  );

drop policy if exists boundaries_select on public.field_boundaries;
create policy boundaries_select on public.field_boundaries for select to authenticated
  using (
    owner_id = (select auth.uid())
    or public.can_review_boundary(id)
  );

drop policy if exists boundaries_insert on public.field_boundaries;
create policy boundaries_insert on public.field_boundaries for insert to authenticated
  with check (
    owner_id = (select auth.uid()) and public.owns_field(field_id)
  );

drop policy if exists assessments_insert on public.assessments;
create policy assessments_insert on public.assessments for insert to authenticated
  with check (
    owner_id = (select auth.uid()) and public.owns_field(field_id)
  );
