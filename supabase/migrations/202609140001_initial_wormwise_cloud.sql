-- WormWise cloud schema v1
-- Apply through Supabase migrations. Never embed the service_role key in Flutter.

create extension if not exists pgcrypto;

create type public.account_kind as enum ('anonymous', 'registered', 'expert', 'admin');
create type public.sync_record_status as enum ('active', 'archived', 'deleted');
create type public.assessment_status as enum ('draft', 'in_progress', 'completed', 'submitted');
create type public.case_status as enum ('pending', 'claimed', 'needs_information', 'advice_sent', 'closed');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_kind public.account_kind not null default 'anonymous',
  display_name text,
  phone text,
  email text,
  preferred_language text not null default 'en',
  organization text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_name_length check (display_name is null or char_length(display_name) between 1 and 120)
);

create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(user_id, account_kind, email, phone)
  values (
    new.id,
    case when coalesce(new.is_anonymous, false)
      then 'anonymous'::public.account_kind
      else 'registered'::public.account_kind
    end,
    new.email,
    new.phone
  ) on conflict (user_id) do update set
    account_kind = case
      when profiles.account_kind in ('expert', 'admin') then profiles.account_kind
      else excluded.account_kind
    end,
    email = excluded.email,
    phone = excluded.phone,
    updated_at = now();
  return new;
end;
$$;

create trigger auth_user_profile_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_auth_user();

create trigger auth_user_profile_identity_updated
  after update of is_anonymous, email, phone on auth.users
  for each row execute procedure public.create_profile_for_auth_user();

insert into public.profiles(user_id, account_kind, email, phone)
select id,
  case when coalesce(is_anonymous, false)
    then 'anonymous'::public.account_kind
    else 'registered'::public.account_kind
  end,
  email,
  phone
from auth.users
on conflict (user_id) do nothing;

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  platform text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(owner_id, installation_id)
);

create table public.fields (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  barangay text,
  municipality_city text not null default 'Piat',
  province text not null default 'Cagayan',
  location_description text,
  is_current boolean not null default false,
  status public.sync_record_status not null default 'active',
  client_updated_at timestamptz not null,
  server_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint field_name_length check (char_length(name) between 1 and 160)
);

create unique index one_current_field_per_owner
  on public.fields(owner_id) where is_current and status = 'active';

create table public.field_boundaries (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  field_id uuid not null references public.fields(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  geometry_geojson jsonb not null,
  area_hectares numeric(12,6) not null check (area_hectares > 0),
  centroid_latitude double precision check (centroid_latitude between -90 and 90),
  centroid_longitude double precision check (centroid_longitude between -180 and 180),
  source_method text not null,
  client_updated_at timestamptz not null,
  server_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(field_id, version_number)
);

create table public.assessments (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  field_id uuid not null references public.fields(id) on delete restrict,
  boundary_id uuid references public.field_boundaries(id) on delete restrict,
  status public.assessment_status not null default 'draft',
  growth_stage text not null,
  protocol_version text not null,
  formula_version text not null,
  result_snapshot jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  submitted_at timestamptz,
  client_updated_at timestamptz not null,
  server_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint submitted_assessment_is_complete check (
    status <> 'submitted' or (completed_at is not null and result_snapshot is not null)
  )
);

create table public.evidence_files (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  storage_path text not null unique,
  station_number integer check (station_number is null or station_number > 0),
  plant_number integer check (plant_number is null or plant_number > 0),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  sha256 text,
  captured_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.expert_cases (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  assessment_id uuid not null unique references public.assessments(id) on delete restrict,
  status public.case_status not null default 'pending',
  farmer_display_name text not null,
  field_name_snapshot text not null,
  barangay_snapshot text not null,
  municipality_snapshot text not null,
  province_snapshot text not null,
  approximate_location_consent boolean not null default false,
  evidence_photo_consent boolean not null default false,
  farmer_question text,
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.case_messages (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.expert_cases(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (char_length(body) between 1 and 8000),
  is_farmer_visible boolean not null default true,
  created_at timestamptz not null default now()
);

create index fields_owner_updated_idx on public.fields(owner_id, updated_at desc);
create index boundaries_field_idx on public.field_boundaries(field_id, version_number desc);
create index assessments_owner_updated_idx on public.assessments(owner_id, updated_at desc);
create index assessments_field_idx on public.assessments(field_id, updated_at desc);
create index evidence_assessment_idx on public.evidence_files(assessment_id);
create index cases_status_created_idx on public.expert_cases(status, created_at);
create index messages_case_created_idx on public.case_messages(case_id, created_at);

create or replace function public.touch_sync_record()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  new.server_version := old.server_version + 1;
  return new;
end;
$$;

create trigger fields_touch before update on public.fields
  for each row execute procedure public.touch_sync_record();
create trigger boundaries_touch before update on public.field_boundaries
  for each row execute procedure public.touch_sync_record();
create trigger assessments_touch before update on public.assessments
  for each row execute procedure public.touch_sync_record();

create or replace function public.is_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid())
      and p.account_kind in ('expert', 'admin')
  );
$$;

create or replace function public.can_review_assessment(target_assessment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_reviewer() and exists (
    select 1 from public.expert_cases c
    where c.assessment_id = target_assessment
  );
$$;

create or replace function public.can_review_evidence(target_assessment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_reviewer() and exists (
    select 1 from public.expert_cases c
    where c.assessment_id = target_assessment
      and c.evidence_photo_consent
  );
$$;

create or replace function public.can_review_storage_object(target_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_reviewer() and exists (
    select 1
    from public.evidence_files e
    join public.expert_cases c on c.assessment_id = e.assessment_id
    where e.storage_path = target_name
      and c.evidence_photo_consent
  );
$$;

create or replace function public.protect_expert_case_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.owner_id <> old.owner_id
     or new.assessment_id <> old.assessment_id
     or new.farmer_display_name <> old.farmer_display_name
     or new.field_name_snapshot <> old.field_name_snapshot
     or new.barangay_snapshot <> old.barangay_snapshot
     or new.municipality_snapshot <> old.municipality_snapshot
     or new.province_snapshot <> old.province_snapshot
     or new.approximate_location_consent <> old.approximate_location_consent
     or new.evidence_photo_consent <> old.evidence_photo_consent then
    raise exception 'Submitted case identity and consent snapshot is immutable';
  end if;
  if new.claimed_by is distinct from old.claimed_by
     and new.claimed_by is distinct from (select auth.uid()) then
    raise exception 'A reviewer may only claim a case for themselves';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger expert_case_protected_update
  before update on public.expert_cases
  for each row execute procedure public.protect_expert_case_fields();

revoke all on function public.is_reviewer() from public;
revoke all on function public.can_review_assessment(uuid) from public;
grant execute on function public.is_reviewer() to authenticated;
grant execute on function public.can_review_assessment(uuid) to authenticated;
revoke all on function public.can_review_evidence(uuid) from public;
grant execute on function public.can_review_evidence(uuid) to authenticated;
revoke all on function public.can_review_storage_object(text) from public;
grant execute on function public.can_review_storage_object(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.fields enable row level security;
alter table public.field_boundaries enable row level security;
alter table public.assessments enable row level security;
alter table public.evidence_files enable row level security;
alter table public.expert_cases enable row level security;
alter table public.case_messages enable row level security;

create policy profiles_read_self on public.profiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy profiles_insert_self on public.profiles for insert to authenticated
  with check (
    user_id = (select auth.uid()) and account_kind = case
      when coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
        then 'anonymous'::public.account_kind
      else 'registered'::public.account_kind
    end
  );
create policy profiles_update_self on public.profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid()) and account_kind = case
      when coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
        then 'anonymous'::public.account_kind
      else 'registered'::public.account_kind
    end
  );

create policy devices_owner_all on public.devices for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy fields_owner_select on public.fields for select to authenticated
  using (owner_id = (select auth.uid()) or (public.is_reviewer() and exists (
    select 1 from public.assessments a join public.expert_cases c on c.assessment_id = a.id
    where a.field_id = fields.id and c.approximate_location_consent
  )));
create policy fields_owner_insert on public.fields for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy fields_owner_update on public.fields for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy fields_owner_delete on public.fields for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy boundaries_select on public.field_boundaries for select to authenticated
  using (owner_id = (select auth.uid()) or (public.is_reviewer() and exists (
    select 1 from public.assessments a join public.expert_cases c on c.assessment_id = a.id
    where a.boundary_id = field_boundaries.id and c.approximate_location_consent
  )));
create policy boundaries_insert on public.field_boundaries for insert to authenticated
  with check (owner_id = (select auth.uid()) and exists (
    select 1 from public.fields f where f.id = field_id and f.owner_id = (select auth.uid())
  ));
create policy boundaries_update on public.field_boundaries for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy boundaries_delete on public.field_boundaries for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy assessments_select on public.assessments for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_review_assessment(id));
create policy assessments_insert on public.assessments for insert to authenticated
  with check (owner_id = (select auth.uid()) and exists (
    select 1 from public.fields f where f.id = field_id and f.owner_id = (select auth.uid())
  ));
create policy assessments_update_unsubmitted on public.assessments for update to authenticated
  using (owner_id = (select auth.uid()) and status <> 'submitted')
  with check (owner_id = (select auth.uid()));
create policy assessments_delete_unsubmitted on public.assessments for delete to authenticated
  using (owner_id = (select auth.uid()) and status <> 'submitted');

create policy evidence_select on public.evidence_files for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_review_evidence(assessment_id));
create policy evidence_insert on public.evidence_files for insert to authenticated
  with check (owner_id = (select auth.uid()) and exists (
    select 1 from public.assessments a
    where a.id = assessment_id and a.owner_id = (select auth.uid()) and a.status <> 'submitted'
  ));
create policy evidence_delete_unsubmitted on public.evidence_files for delete to authenticated
  using (owner_id = (select auth.uid()) and exists (
    select 1 from public.assessments a
    where a.id = assessment_id and a.status <> 'submitted'
  ));

create policy cases_farmer_or_reviewer_read on public.expert_cases for select to authenticated
  using (owner_id = (select auth.uid()) or public.is_reviewer());
create policy cases_farmer_submit on public.expert_cases for insert to authenticated
  with check (
    owner_id = (select auth.uid()) and claimed_by is null and status = 'pending'
    and exists (select 1 from public.assessments a
      where a.id = assessment_id and a.owner_id = (select auth.uid()) and a.status = 'submitted')
  );
create policy cases_reviewer_update on public.expert_cases for update to authenticated
  using (public.is_reviewer()) with check (public.is_reviewer());

create policy messages_participant_read on public.case_messages for select to authenticated
  using (exists (
    select 1 from public.expert_cases c where c.id = case_id
      and ((c.owner_id = (select auth.uid()) and is_farmer_visible) or public.is_reviewer())
  ));
create policy messages_participant_insert on public.case_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and exists (
    select 1 from public.expert_cases c where c.id = case_id
      and (c.owner_id = (select auth.uid()) or public.is_reviewer())
  ));

-- Evidence objects are private. Expected path: <owner_uuid>/<assessment_uuid>/<file>.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'assessment-evidence',
  'assessment-evidence',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy evidence_storage_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'assessment-evidence' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy evidence_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'assessment-evidence' and (
    owner_id = (select auth.uid())::text or public.can_review_storage_object(name)
  ));
create policy evidence_storage_delete_owner on storage.objects for delete to authenticated
  using (bucket_id = 'assessment-evidence' and owner_id = (select auth.uid())::text);

grant select, insert, update, delete on public.profiles, public.devices, public.fields,
  public.field_boundaries, public.assessments, public.evidence_files,
  public.expert_cases, public.case_messages to authenticated;
revoke all on all tables in schema public from anon;
