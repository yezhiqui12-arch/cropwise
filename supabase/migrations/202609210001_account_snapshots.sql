-- Private, per-account snapshots of WormWise's complete on-device records and
-- assessment evidence. These are separate from the partial relational sync.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'wormwise-account-backups',
  'wormwise-account-backups',
  false,
  52428800,
  array['application/gzip', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy wormwise_backup_read_own on storage.objects for select to authenticated
  using (
    bucket_id = 'wormwise-account-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy wormwise_backup_insert_own on storage.objects for insert to authenticated
  with check (
    bucket_id = 'wormwise-account-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy wormwise_backup_update_own on storage.objects for update to authenticated
  using (
    bucket_id = 'wormwise-account-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'wormwise-account-backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
