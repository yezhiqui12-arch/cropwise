-- Shared field catalogs. Piat locations are maintained against PSA PSGC.
begin;
create table public.piat_barangays (
  psgc_code text primary key check (psgc_code ~ '^020152[0-9]{4}$' and psgc_code <> '0201520000'),
  municipality_code text not null default '0201520000' check (municipality_code = '0201520000'),
  name text not null unique check (char_length(trim(name)) between 1 and 100),
  active boolean not null default true,
  source_url text not null default 'https://psa.gov.ph/classification/psgc/barangays/0201520000',
  updated_at timestamptz not null default now()
);
insert into public.piat_barangays(psgc_code,name) values
('0201520001','Apayao'),('0201520002','Aquib'),('0201520003','Dugayung'),
('0201520004','Gumarueng'),('0201520005','Macapil'),('0201520006','Maguilling'),
('0201520007','Minanga'),('0201520008','Poblacion I'),('0201520011','Santa Barbara'),
('0201520012','Santo Domingo'),('0201520013','Sicatna'),('0201520014','Villa Rey'),
('0201520015','Warat'),('0201520016','Baung'),('0201520017','Calaoagan'),
('0201520018','Catarauan'),('0201520019','Poblacion II'),('0201520020','Villa Reyno');
create function public.normalize_maize_variety(value text) returns text
language sql immutable set search_path = '' as $$
 select regexp_replace(lower(trim(value)), '[^a-z0-9]', '', 'g');
$$;
create table public.maize_varieties (
 id uuid primary key default gen_random_uuid(), name text not null,
 normalized_name text generated always as (public.normalize_maize_variety(name)) stored unique,
 created_at timestamptz not null default now(),
 check(char_length(trim(name)) between 2 and 120), check(normalized_name <> '')
);
create table public.maize_variety_aliases (
 normalized_name text primary key,
 variety_id uuid not null references public.maize_varieties(id),
 check(normalized_name <> '')
);
create table public.maize_variety_suggestions (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 name text not null check(char_length(trim(name)) between 2 and 120),
 normalized_name text generated always as (public.normalize_maize_variety(name)) stored,
 status text not null default 'pending' check(status in ('pending','approved','merged','rejected')),
 variety_id uuid references public.maize_varieties(id), reason text,
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), check(normalized_name <> '')
);
create unique index maize_pending_unique on public.maize_variety_suggestions(normalized_name) where status='pending';
insert into public.maize_varieties(name) values ('Pioneer P3530YHR'),('Pioneer 30T80'),
 ('Dekalb DK 8131S'),('NK 6410'),('NK 8840'),
 ('IPB Var 6');
alter table public.piat_barangays enable row level security;
alter table public.maize_varieties enable row level security;
alter table public.maize_variety_aliases enable row level security;
alter table public.maize_variety_suggestions enable row level security;
create policy piat_catalog_read on public.piat_barangays for select to authenticated using(true);
create policy piat_catalog_admin on public.piat_barangays for all to authenticated
 using(exists(select 1 from public.profiles where user_id=(select auth.uid()) and account_kind='admin'))
 with check(exists(select 1 from public.profiles where user_id=(select auth.uid()) and account_kind='admin'));
create policy variety_read on public.maize_varieties for select to authenticated using(true);
create policy variety_alias_read on public.maize_variety_aliases for select to authenticated using(true);
create policy suggestion_read on public.maize_variety_suggestions for select to authenticated
 using(owner_id=(select auth.uid()) or public.is_reviewer());
grant select on public.piat_barangays,public.maize_varieties,public.maize_variety_aliases,public.maize_variety_suggestions to authenticated;
grant insert,update on public.piat_barangays to authenticated;

create function public.suggest_maize_variety(p_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_key text := public.normalize_maize_variety(p_name); v_id uuid; v_name text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if char_length(trim(p_name)) not between 2 and 120 or v_key='' then raise exception 'Enter a valid variety name (2–120 characters)'; end if;
 if v_key in ('pioneer','dekalb','nk','bioseed') then raise exception 'Enter a specific hybrid or variety, not only a brand'; end if;
 perform pg_advisory_xact_lock(hashtextextended('maize-catalog',0));
 select id,name into v_id,v_name from public.maize_varieties where normalized_name=v_key;
 if v_id is null then
  select v.id,v.name into v_id,v_name from public.maize_variety_aliases a join public.maize_varieties v on v.id=a.variety_id where a.normalized_name=v_key;
 end if;
 if v_id is not null then return jsonb_build_object('status','existing','name',v_name); end if;
 if not exists(select 1 from public.maize_variety_suggestions where normalized_name=v_key and status='pending') then
  if (select count(*) from public.maize_variety_suggestions where owner_id=auth.uid() and created_at>now()-interval '1 day') >=20 then raise exception 'Daily suggestion limit reached'; end if;
  insert into public.maize_variety_suggestions(owner_id,name) values(auth.uid(),trim(p_name));
 end if;
 return jsonb_build_object('status','pending','name',trim(p_name));
end; $$;

create function public.review_maize_variety(p_id uuid,p_action text,p_target uuid default null,p_reason text default null) returns void
language plpgsql security definer set search_path='' as $$
declare s public.maize_variety_suggestions; v_id uuid;
begin
 if not public.is_reviewer() then raise exception 'Expert or administrator access required'; end if;
 perform pg_advisory_xact_lock(hashtextextended('maize-catalog',0));
 select * into s from public.maize_variety_suggestions where id=p_id and status='pending' for update;
 if s.id is null then raise exception 'Suggestion is no longer pending'; end if;
 if p_action='approve' then
  select id into v_id from public.maize_varieties where normalized_name=s.normalized_name;
  if v_id is null then select variety_id into v_id from public.maize_variety_aliases where normalized_name=s.normalized_name; end if;
  if v_id is null then insert into public.maize_varieties(name) values(s.name) returning id into v_id; end if;
 elsif p_action='merge' then
  select id into v_id from public.maize_varieties where id=p_target;
  if v_id is null then raise exception 'Choose an existing variety'; end if;
  if exists(select 1 from public.maize_varieties where normalized_name=s.normalized_name and id<>v_id) then raise exception 'This name already belongs to another variety'; end if;
  insert into public.maize_variety_aliases(normalized_name,variety_id) values(s.normalized_name,v_id)
   on conflict(normalized_name) do nothing;
 elsif p_action='reject' then
  if char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Provide a rejection reason (3–500 characters)'; end if;
 else raise exception 'Invalid review action'; end if;
 update public.maize_variety_suggestions set status=case p_action when 'approve' then 'approved' when 'merge' then 'merged' else 'rejected' end,
  variety_id=v_id,reason=left(trim(p_reason),500),reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
end; $$;
revoke all on function public.suggest_maize_variety(text), public.review_maize_variety(uuid,text,uuid,text) from public;
grant execute on function public.suggest_maize_variety(text), public.review_maize_variety(uuid,text,uuid,text) to authenticated;

-- Only the server-side PSA refresh function may replace the official list.
create function public.refresh_piat_catalog(p_rows jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 100 then raise exception 'Invalid official list'; end if;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(psgc_code text,name text)
   where psgc_code is null or psgc_code !~ '^020152[0-9]{4}$' or psgc_code='0201520000' or name is null or char_length(trim(name)) not between 1 and 100)
 then raise exception 'Only valid Piat barangays are allowed'; end if;
 insert into public.piat_barangays(psgc_code,name,active,updated_at)
 select psgc_code,trim(name),true,now() from jsonb_to_recordset(p_rows) as r(psgc_code text,name text)
 on conflict(psgc_code) do update set name=excluded.name,active=true,updated_at=now();
 update public.piat_barangays set active=false,updated_at=now()
 where active and psgc_code not in(select r.psgc_code from jsonb_to_recordset(p_rows) as r(psgc_code text));
end; $$;
revoke all on function public.refresh_piat_catalog(jsonb) from public,authenticated;
grant execute on function public.refresh_piat_catalog(jsonb) to service_role;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
   select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='maize_variety_suggestions') then
  alter publication supabase_realtime add table public.maize_variety_suggestions;
 end if;
end $$;
commit;
