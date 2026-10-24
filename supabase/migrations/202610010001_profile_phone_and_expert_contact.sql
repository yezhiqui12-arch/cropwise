-- Contact phone is profile information, not an Auth/SMS sign-in number.
begin;
create or replace function public.set_own_profile_phone(p_phone text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_phone text := nullif(trim(p_phone), '');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_phone is not null and (
    length(v_phone) > 40 or v_phone !~ '^\+?[0-9 ()-]+$' or
    length(regexp_replace(v_phone, '[^0-9]', '', 'g')) not between 7 and 15
  ) then raise exception 'Enter a valid phone number with 7 to 15 digits'; end if;
  update public.profiles set phone = v_phone, updated_at = now()
  where user_id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;
end;
$$;
revoke all on function public.set_own_profile_phone(text) from public;
grant execute on function public.set_own_profile_phone(text) to authenticated;

-- Keep the dashboard profile form and mobile profile on the same validation.
create or replace function public.update_dashboard_profile(p_name text, p_phone text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles
    where user_id = auth.uid() and account_kind in ('admin', 'expert')) then
    raise exception 'Dashboard access required';
  end if;
  if nullif(trim(p_name), '') is null or length(trim(p_name)) > 120 then
    raise exception 'Name must be 1 to 120 characters';
  end if;
  perform public.set_own_profile_phone(p_phone);
  update public.profiles set display_name = trim(p_name), updated_at = now()
  where user_id = auth.uid();
end;
$$;
revoke all on function public.update_dashboard_profile(text,text) from public;
grant execute on function public.update_dashboard_profile(text,text) to authenticated;

-- Expose only the assigned reviewer's contact for cases owned by the caller.
-- Do not grant farmers access to the complete expert profile directory.
create or replace function public.get_my_expert_contacts()
returns table(case_id uuid, expert_id uuid, display_name text, phone text)
language sql stable security definer set search_path = '' as $$
  select c.id, p.user_id, p.display_name, p.phone
  from public.expert_cases c
  join public.profiles p on p.user_id = c.claimed_by
  where c.owner_id = auth.uid() and p.account_kind in ('expert', 'admin');
$$;
revoke all on function public.get_my_expert_contacts() from public;
grant execute on function public.get_my_expert_contacts() to authenticated;

-- Auth email/identity updates must not erase a manually entered contact phone.
create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(user_id, account_kind, email, phone)
  values (new.id,
    case when coalesce(new.is_anonymous, false)
      then 'anonymous'::public.account_kind else 'registered'::public.account_kind end,
    new.email, new.phone)
  on conflict (user_id) do update set
    account_kind = case when profiles.account_kind in ('expert', 'admin')
      then profiles.account_kind else excluded.account_kind end,
    email = excluded.email,
    phone = profiles.phone,
    updated_at = now();
  return new;
end;
$$;
commit;
