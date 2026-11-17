-- REVIEW ONLY / READ ONLY. Audit bucket access without uploading files or using student credentials.
-- A private bucket does NOT itself prove correct authenticated RLS or signed URL behavior.
select b.id as bucket_id,b.public,b.file_size_limit,b.allowed_mime_types,
       coalesce((select jsonb_agg(jsonb_build_object('name',p.policyname,'command',p.cmd,'roles',p.roles) order by p.policyname)
         from pg_policies p where p.schemaname='storage' and p.tablename='objects'
           and (coalesce(p.qual,'') like '%'||b.id||'%' or coalesce(p.with_check,'') like '%'||b.id||'%')),'[]'::jsonb) as explicitly_named_object_policies
from storage.buckets b where b.id in ('cq-v4-originals','cq-v4-speaking') order by b.id;
-- PDF access can be brokered by a separate authenticated endpoint; no direct bucket-specific
-- storage.objects policy is NOT proof of missing PDF access. Confirm the actual PDF transport.
-- Never use a student token or upload to production for this audit.
