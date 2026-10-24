begin;
create temp table advisor_checks (result text);
do $$
declare
  uid uuid;
  pid constant uuid := '00000000-0000-0000-0000-000000000000';
  r jsonb;
  n integer;
begin
  if has_function_privilege('anon','public.reserve_advisor_attempt(uuid)','EXECUTE') or
     has_function_privilege('authenticated','public.reserve_advisor_attempt(uuid)','EXECUTE') or
     not has_function_privilege('service_role','public.reserve_advisor_attempt(uuid)','EXECUTE') then raise exception 'RPC permissions failed'; end if;
  insert into advisor_checks values ('RPC restricted to service role');
  if has_table_privilege('anon','public.advisor_request_counters','SELECT') or
     has_table_privilege('authenticated','public.advisor_request_counters','UPDATE') or
     not (select relrowsecurity from pg_class where oid='public.advisor_request_counters'::regclass) then raise exception 'Table protection failed'; end if;
  insert into advisor_checks values ('Counter table protected by RLS and grants');
  select id into uid from auth.users where deleted_at is null limit 1;
  if uid is null then raise exception 'No account for rollback-only check'; end if;
  begin
    perform public.reserve_advisor_attempt(pid);
    raise exception 'Invalid user accepted';
  exception when invalid_parameter_value then null; end;
  insert into advisor_checks values ('Invalid user rejected');
  insert into public.advisor_request_counters(subject,minute_start,day_start) values
    (uid,date_trunc('minute',clock_timestamp()),date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC'),
    (pid,date_trunc('minute',clock_timestamp()),date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC')
    on conflict(subject) do update set minute_start=excluded.minute_start,day_start=excluded.day_start,minute_count=0,day_count=0;
  for n in 1..18 loop
    r := public.reserve_advisor_attempt(uid);
    if r->>'allowed' <> 'true' then raise exception 'Attempt % rejected early',n; end if;
  end loop;
  r := public.reserve_advisor_attempt(uid);
  if r->>'allowed' <> 'false' or r->>'scope' <> 'user' or (r->>'retry_after')::integer < 1 then raise exception 'Minute user limit failed'; end if;
  if (select day_count from public.advisor_request_counters where subject=pid) <> 18 then raise exception 'Denied attempt changed counter'; end if;
  insert into advisor_checks values ('18 user attempts allowed; 19th rejected without increment');
  update public.advisor_request_counters set minute_count=0, day_count=case when subject=uid then 180 else 0 end where subject in(uid,pid);
  r := public.reserve_advisor_attempt(uid);
  if r->>'allowed' <> 'false' or r->>'scope' <> 'user' then raise exception 'Daily user limit failed'; end if;
  insert into advisor_checks values ('180/day user cap enforced');
  update public.advisor_request_counters set day_count=0,minute_count=case when subject=pid then 120 else 0 end where subject in(uid,pid);
  r := public.reserve_advisor_attempt(uid);
  if r->>'allowed' <> 'false' or r->>'scope' <> 'project' then raise exception 'Project minute limit failed'; end if;
  insert into advisor_checks values ('120/minute project cap enforced');
  update public.advisor_request_counters set minute_count=0,day_count=case when subject=pid then 1500 else 0 end where subject in(uid,pid);
  r := public.reserve_advisor_attempt(uid);
  if r->>'allowed' <> 'false' or r->>'scope' <> 'project' then raise exception 'Project daily limit failed'; end if;
  insert into advisor_checks values ('1500/day project cap enforced');
  update public.advisor_request_counters set minute_start=clock_timestamp()-interval '1 day',day_start=clock_timestamp()-interval '2 days',minute_count=9999,day_count=9999 where subject in(uid,pid);
  r := public.reserve_advisor_attempt(uid);
  if r->>'allowed' <> 'true' or (select day_count from public.advisor_request_counters where subject=pid)<>1 then raise exception 'Window reset failed'; end if;
  insert into advisor_checks values ('Expired minute/day counters reset');
end;
$$;
select jsonb_build_object('passed',count(*),'checks',jsonb_agg(result),'AI calls',0,'counter changes','rolled back') as advisor_verification from advisor_checks;
rollback;
