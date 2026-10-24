-- Privacy is inherited from assessment_stations: reviewers require location consent.
alter table public.assessment_stations
  add column if not exists location_source text not null default 'unverified',
  add column if not exists location_captured_at timestamptz,
  add column if not exists plant_locations jsonb not null default '[]'::jsonb;
alter table public.assessment_stations add constraint plant_locations_array
  check (jsonb_typeof(plant_locations) = 'array');
comment on column public.assessment_stations.plant_locations is
  'Plant observations with photo-time phone GPS, accuracy and timestamps; missing fixes remain null.';
