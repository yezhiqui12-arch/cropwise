-- A guest proves possession of its Supabase session before OAuth replaces it.
-- Only the account holding the one-time token may read that guest's records.
create table public.guest_account_handoffs (
  token_hash text primary key,
  guest_id uuid not null references auth.users(id),
  expires_at timestamptz not null,
  consumed_at timestamptz
);

create table public.guest_account_links (
  guest_id uuid primary key references auth.users(id),
  account_id uuid not null references auth.users(id),
  linked_at timestamptz not null default now(),
  constraint different_guest_and_account check (guest_id <> account_id)
);

alter table public.guest_account_handoffs enable row level security;
alter table public.guest_account_links enable row level security;
revoke all on public.guest_account_handoffs, public.guest_account_links from anon, authenticated;

create or replace function public.begin_guest_account_handoff()
returns text language plpgsql security definer set search_path = '' as $$
declare
  token text;
begin
  if (select auth.uid()) is null or not exists (
    select 1 from auth.users
    where id = (select auth.uid()) and is_anonymous
  ) then
    raise exception 'An active guest session is required';
  end if;
  token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.guest_account_handoffs(token_hash, guest_id, expires_at)
  values (encode(sha256(convert_to(token, 'UTF8')), 'hex'), (select auth.uid()), now() + interval '1 hour');
  return token;
end;
$$;

create or replace function public.finish_guest_account_handoff(token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  source_id uuid;
begin
  if (select auth.uid()) is null or exists (
    select 1 from auth.users
    where id = (select auth.uid()) and is_anonymous
  ) then
    raise exception 'A registered account session is required';
  end if;
  update public.guest_account_handoffs
     set consumed_at = now()
   where token_hash = encode(sha256(convert_to(token, 'UTF8')), 'hex')
     and expires_at > now() and consumed_at is null
  returning guest_id into source_id;
  if source_id is null then return false; end if;
  insert into public.guest_account_links(guest_id, account_id)
  values (source_id, (select auth.uid()))
  on conflict (guest_id) do nothing;
  return exists (
    select 1 from public.guest_account_links
    where guest_id = source_id and account_id = (select auth.uid())
  );
end;
$$;

-- Returns only records from a guest explicitly linked to the caller. The
-- complete local Drift backup remains the preferred restore source.
create or replace function public.linked_guest_cloud_records()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'guest_id', l.guest_id,
    'fields', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from public.fields f where f.owner_id = l.guest_id),
    'boundaries', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from public.field_boundaries b where b.owner_id = l.guest_id),
    'assessments', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.assessments a where a.owner_id = l.guest_id),
    'stations', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) from public.assessment_stations s where s.owner_id = l.guest_id),
    'evidence', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) from public.evidence_files e where e.owner_id = l.guest_id)
  )), '[]'::jsonb)
  from public.guest_account_links l
  where l.account_id = (select auth.uid());
$$;

create or replace function public.can_read_linked_guest_evidence(object_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.guest_account_links l
    where l.account_id = (select auth.uid())
      and l.guest_id::text = (storage.foldername(object_name))[1]
  );
$$;

revoke all on function public.begin_guest_account_handoff(),
  public.finish_guest_account_handoff(text),
  public.linked_guest_cloud_records(),
  public.can_read_linked_guest_evidence(text) from public;
grant execute on function public.begin_guest_account_handoff(),
  public.finish_guest_account_handoff(text),
  public.linked_guest_cloud_records(),
  public.can_read_linked_guest_evidence(text) to authenticated;

create policy linked_guest_evidence_read on storage.objects for select to authenticated
  using (
    bucket_id = 'assessment-evidence'
    and public.can_read_linked_guest_evidence(name)
  );
