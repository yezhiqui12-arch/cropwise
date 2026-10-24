begin;
-- Per-device manifests contain paths/checksums only, never credentials. Existing
-- account-folder read/insert/update policies continue to enforce ownership.
update storage.buckets
set allowed_mime_types = array['application/gzip', 'application/json', 'image/jpeg', 'image/png', 'image/webp']
where id = 'wormwise-account-backups';

create policy wormwise_backup_delete_own_snapshots
on storage.objects for delete to authenticated
using (
  bucket_id = 'wormwise-account-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (
    name ~ ('^' || (select auth.uid())::text || '/devices/[a-f0-9]{32}/snapshot-[0-9]+(-[a-f0-9]{16})?[.]json[.]gz$')
    or name ~ ('^' || (select auth.uid())::text || '/[a-f0-9]{32}-[0-9]+[.]json[.]gz$')
  )
);
commit;
