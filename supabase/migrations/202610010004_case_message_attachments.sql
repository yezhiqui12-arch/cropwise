begin;

alter table public.case_messages
  add column if not exists attachments jsonb not null default '[]'::jsonb,
  add column if not exists message_kind text not null default 'message',
  add column if not exists requested_station integer,
  add column if not exists requested_plant integer,
  add column if not exists request_message_id uuid references public.case_messages(id);
alter table public.case_messages drop constraint if exists case_messages_body_check;
alter table public.case_messages add constraint case_message_content_check check (
  char_length(body) <= 8000 and (char_length(trim(body)) > 0 or jsonb_array_length(attachments) > 0)
);
alter table public.case_messages add constraint case_message_attachment_shape check (
  jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 5
  and message_kind in ('message','evidence_request')
  and (requested_station is null or requested_station > 0)
  and (requested_plant is null or requested_plant > 0)
  and (requested_plant is null or requested_station is not null)
);

create or replace function public.can_send_case_message(p_case_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.expert_cases c where c.id = p_case_id
    and c.status <> 'closed' and (c.owner_id = auth.uid() or exists (
      select 1 from public.profiles p where p.user_id = auth.uid()
      and (p.account_kind = 'admin' or (p.account_kind = 'expert' and c.claimed_by = auth.uid()))
    )));
$$;

create or replace function public.can_read_case_message_object(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.case_messages m
    join public.expert_cases c on c.id = m.case_id
    where exists (select 1 from jsonb_array_elements(m.attachments) a where a->>'storage_path' = p_path)
    and ((c.owner_id = auth.uid() and m.is_farmer_visible) or exists (
      select 1 from public.profiles p where p.user_id = auth.uid()
      and (p.account_kind = 'admin' or (p.account_kind = 'expert' and c.claimed_by = auth.uid()))
    )));
$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('case-message-images','case-message-images',false,10485760,
  array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false, file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- Paths are <case>/<sender>/<message>/<attachment>.jpg. Staged uploads are
-- readable only by their sender; others see them only after atomic publication.
create policy case_message_image_upload on storage.objects for insert to authenticated
with check (bucket_id = 'case-message-images'
  and (storage.foldername(name))[2] = auth.uid()::text
  and array_length(storage.foldername(name),1) = 3
  and exists (select 1 from public.expert_cases c where c.id::text = (storage.foldername(name))[1]
    and public.can_send_case_message(c.id)));
create policy case_message_image_read on storage.objects for select to authenticated
using (bucket_id = 'case-message-images' and (
  (storage.foldername(name))[2] = auth.uid()::text or public.can_read_case_message_object(name)));
create policy case_message_image_discard on storage.objects for delete to authenticated
using (bucket_id = 'case-message-images' and (storage.foldername(name))[2] = auth.uid()::text
  and not exists (select 1 from public.case_messages m
    where exists (select 1 from jsonb_array_elements(m.attachments) a where a->>'storage_path' = name)));

-- Legacy text clients remain supported. Attachments and structured requests
-- must pass the RPC below; clients cannot insert unvalidated object paths.
drop policy if exists messages_participant_insert on public.case_messages;
create policy messages_participant_insert on public.case_messages for insert to authenticated
with check (sender_id = auth.uid() and public.can_send_case_message(case_id)
  and attachments = '[]'::jsonb and message_kind = 'message'
  and requested_station is null and requested_plant is null and request_message_id is null);

create or replace function public.send_case_message(
  p_message_id uuid, p_case_id uuid, p_body text,
  p_attachments jsonb default '[]'::jsonb, p_kind text default 'message',
  p_requested_station integer default null, p_requested_plant integer default null,
  p_request_message_id uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_case public.expert_cases;
  v_existing public.case_messages;
  v_attachment jsonb;
  v_clean jsonb := '[]'::jsonb;
  v_path text;
  v_station integer;
  v_plant integer;
  v_body text := trim(coalesce(p_body,''));
  v_owner boolean;
  v_role text;
begin
  if auth.uid() is null or p_message_id is null then raise exception 'Sign in to send a message'; end if;
  select * into v_case from public.expert_cases where id = p_case_id for update;
  v_owner := v_case.owner_id = auth.uid();
  select * into v_existing from public.case_messages where id = p_message_id;
  if v_existing.id is not null then
    if v_existing.case_id = p_case_id and v_existing.sender_id = auth.uid() then
      return v_existing.id; -- A retry after lost acknowledgement cannot duplicate.
    end if;
    raise exception 'Message identifier is already in use';
  end if;
  if not public.can_send_case_message(p_case_id) then raise exception 'An open case and participant access are required'; end if;
  if p_kind not in ('message','evidence_request') or (p_kind = 'evidence_request' and v_owner) then
    raise exception 'Only the assigned expert or admin can request evidence';
  end if;
  if p_attachments is null or jsonb_typeof(p_attachments) <> 'array' then raise exception 'Invalid attachments'; end if;
  if jsonb_array_length(p_attachments) > 5 then raise exception 'Attach at most five photos'; end if;
  if char_length(v_body) > 8000 or (v_body = '' and jsonb_array_length(p_attachments) = 0)
    or (p_kind = 'evidence_request' and v_body = '') then raise exception 'Add a message or photo'; end if;
  if (p_requested_station is not null and p_requested_station <= 0)
    or (p_requested_plant is not null and (p_requested_plant <= 0 or p_requested_station is null)) then
    raise exception 'Choose a positive station and plant number';
  end if;
  if p_request_message_id is not null and not exists (select 1 from public.case_messages m
    where m.id = p_request_message_id and m.case_id = p_case_id and m.message_kind = 'evidence_request'
    and m.is_farmer_visible) then raise exception 'Evidence request must belong to this case'; end if;
  v_role := case when v_owner then 'field_evidence' else 'expert_reference' end;
  for v_attachment in select value from jsonb_array_elements(p_attachments) loop
    v_path := v_attachment->>'storage_path';
    if v_path is null or v_path !~ ('^' || p_case_id::text || '/' || auth.uid()::text || '/' || p_message_id::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$')
      or exists (select 1 from jsonb_array_elements(v_clean) a where a->>'storage_path' = v_path) then
      raise exception 'Invalid or duplicate attachment path';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'case-message-images' and o.name = v_path
      and o.metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')
      and (o.metadata->>'size')::bigint between 1 and 10485760) then
      raise exception 'Upload each photo before sending (maximum 10 MB)';
    end if;
    v_station := nullif(v_attachment->>'station_number','')::integer;
    v_plant := nullif(v_attachment->>'plant_number','')::integer;
    if (v_station is not null and v_station <= 0) or
      (v_plant is not null and (v_plant <= 0 or v_station is null)) then raise exception 'Invalid photo station or plant number'; end if;
    if char_length(coalesce(v_attachment->>'caption','')) > 500 then raise exception 'Photo caption is too long'; end if;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object(
      'storage_path',v_path,'caption',coalesce(v_attachment->>'caption',''),
      'station_number',v_station,'plant_number',v_plant,'purpose',v_role));
  end loop;
  insert into public.case_messages(id,case_id,sender_id,body,is_farmer_visible,
    attachments,message_kind,requested_station,requested_plant,request_message_id)
  values(p_message_id,p_case_id,auth.uid(),v_body,true,v_clean,p_kind,
    p_requested_station,p_requested_plant,p_request_message_id);
  if p_kind = 'evidence_request' then
    update public.expert_cases set status='needs_information',updated_at=now() where id=p_case_id;
  end if;
  return p_message_id;
end;
$$;
revoke all on function public.can_send_case_message(uuid) from public;
revoke all on function public.can_read_case_message_object(text) from public;
revoke all on function public.send_case_message(uuid,uuid,text,jsonb,text,integer,integer,uuid) from public;
grant execute on function public.can_send_case_message(uuid) to authenticated;
grant execute on function public.can_read_case_message_object(text) to authenticated;
grant execute on function public.send_case_message(uuid,uuid,text,jsonb,text,integer,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
