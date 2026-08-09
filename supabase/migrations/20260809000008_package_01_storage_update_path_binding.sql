-- AUD-04: Storage UPDATE must validate the post-update object name against its batch-generated path.
drop policy if exists source_evidence_admin_update on storage.objects;
create policy source_evidence_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'source-evidence' and public.is_admin() and exists (
    select 1 from public.import_batches b where b.storage_bucket = bucket_id and b.storage_object_path = name
      and b.created_by = auth.uid() and b.source_verified_at is null))
  with check (bucket_id = 'source-evidence' and public.is_admin() and exists (
    select 1 from public.import_batches b where b.storage_bucket = bucket_id and b.storage_object_path = name
      and b.created_by = auth.uid() and b.source_verified_at is null));
