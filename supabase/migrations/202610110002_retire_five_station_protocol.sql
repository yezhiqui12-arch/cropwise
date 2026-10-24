-- Retire the original five-station W/ladder cloud protocol. NOT VALID allows
-- the identified historical rows to remain until the approved maintenance
-- cleanup runs, while rejecting reuploads from an old phone immediately.
begin;
alter table public.assessments
  add constraint assessments_no_retired_five_station_protocol
  check (
    protocol_version <> 'wormwise-maize-faw-2026.1-draft'
    and coalesce(result_snapshot->>'scouting_pattern','') not in ('w','ladder')
  ) not valid;
commit;
