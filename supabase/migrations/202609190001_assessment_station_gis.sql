-- Cloud projection of privacy-controlled assessment station summaries.
-- Apply after the initial WormWise cloud and RLS migrations.

create table public.assessment_stations (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  block_run_id uuid not null,
  station_number integer not null check (station_number > 0),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  gps_accuracy_m double precision check (gps_accuracy_m is null or gps_accuracy_m >= 0),
  plants_inspected integer not null check (plants_inspected >= 0),
  plants_infested integer not null check (
    plants_infested >= 0 and plants_infested <= plants_inspected
  ),
  station_infestation_percent numeric(6,3) generated always as (
    case
      when plants_inspected = 0 then null
      else (plants_infested::numeric / plants_inspected::numeric) * 100
    end
  ) stored,
  captured_at timestamptz,
  client_updated_at timestamptz not null,
  server_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assessment_id, block_run_id, station_number)
);

create index assessment_stations_assessment_idx
  on public.assessment_stations(assessment_id, station_number);

create trigger assessment_stations_touch before update on public.assessment_stations
  for each row execute procedure public.touch_sync_record();

alter table public.assessment_stations enable row level security;

create policy assessment_stations_select on public.assessment_stations
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or (
      public.is_reviewer()
      and exists (
        select 1
        from public.expert_cases c
        where c.assessment_id = assessment_stations.assessment_id
          and c.approximate_location_consent
      )
    )
  );

create policy assessment_stations_owner_insert on public.assessment_stations
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (
      select 1 from public.assessments a
      where a.id = assessment_stations.assessment_id
        and a.owner_id = (select auth.uid())
    )
  );

create policy assessment_stations_owner_update on public.assessment_stations
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy assessment_stations_owner_delete on public.assessment_stations
  for delete to authenticated
  using (owner_id = (select auth.uid()));

grant select, insert, update, delete on public.assessment_stations to authenticated;
