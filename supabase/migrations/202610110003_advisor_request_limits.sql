begin;
-- Counters contain no prompts. Reserved zero UUID represents the whole project.
create table if not exists public.advisor_request_counters (
  subject uuid primary key,
  minute_start timestamptz not null,
  minute_count integer not null default 0 check (minute_count >= 0),
  day_start timestamptz not null,
  day_count integer not null default 0 check (day_count >= 0)
);
alter table public.advisor_request_counters enable row level security;
revoke all on public.advisor_request_counters from public, anon, authenticated;

create or replace function public.reserve_advisor_attempt(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  project_id constant uuid := '00000000-0000-0000-0000-000000000000';
  now_at timestamptz := clock_timestamp();
  minute_at timestamptz := date_trunc('minute', now_at);
  day_at timestamptz := date_trunc('day', now_at at time zone 'UTC') at time zone 'UTC';
  project_row public.advisor_request_counters%rowtype;
  user_row public.advisor_request_counters%rowtype;
  scope_name text;
  retry_seconds integer;
begin
  if p_user_id is null or p_user_id = project_id or not exists (
    select 1 from auth.users where id = p_user_id and deleted_at is null
  ) then raise exception 'A valid user is required' using errcode = '22023'; end if;
  -- Always lock project first: shared across Edge instances; no check/insert race.
  insert into public.advisor_request_counters(subject, minute_start, day_start)
    values(project_id, minute_at, day_at) on conflict do nothing;
  select * into project_row from public.advisor_request_counters where subject = project_id for update;
  -- Re-read the clock after waiting for the shared lock (minute/day boundary).
  now_at := clock_timestamp();
  minute_at := date_trunc('minute', now_at);
  day_at := date_trunc('day', now_at at time zone 'UTC') at time zone 'UTC';
  insert into public.advisor_request_counters(subject, minute_start, day_start)
    values(p_user_id, minute_at, day_at) on conflict do nothing;
  select * into user_row from public.advisor_request_counters where subject = p_user_id for update;
  if project_row.minute_start < minute_at then project_row.minute_count := 0; end if;
  if project_row.day_start < day_at then project_row.day_count := 0; end if;
  if user_row.minute_start < minute_at then user_row.minute_count := 0; end if;
  if user_row.day_start < day_at then user_row.day_count := 0; end if;
  if project_row.day_count >= 1500 or user_row.day_count >= 180 then
    scope_name := case when project_row.day_count >= 1500 then 'project' else 'user' end;
    retry_seconds := greatest(1, ceil(extract(epoch from day_at + interval '1 day' - now_at))::integer);
  elsif project_row.minute_count >= 120 or user_row.minute_count >= 18 then
    scope_name := case when project_row.minute_count >= 120 then 'project' else 'user' end;
    retry_seconds := greatest(1, ceil(extract(epoch from minute_at + interval '1 minute' - now_at))::integer);
  end if;
  if scope_name is not null then return jsonb_build_object('allowed', false, 'scope', scope_name, 'retry_after', retry_seconds); end if;
  update public.advisor_request_counters set minute_start=minute_at, day_start=day_at,
    minute_count=project_row.minute_count+1, day_count=project_row.day_count+1 where subject=project_id;
  update public.advisor_request_counters set minute_start=minute_at, day_start=day_at,
    minute_count=user_row.minute_count+1, day_count=user_row.day_count+1 where subject=p_user_id;
  return jsonb_build_object('allowed', true);
end;
$$;
revoke all on function public.reserve_advisor_attempt(uuid) from public, anon, authenticated;
grant execute on function public.reserve_advisor_attempt(uuid) to service_role;
comment on function public.reserve_advisor_attempt(uuid) is 'Service-only Gemini attempt budget: user 18/minute 180/UTC day; project 120/minute 1500/UTC day. Each fallback reserves separately.';
commit;
