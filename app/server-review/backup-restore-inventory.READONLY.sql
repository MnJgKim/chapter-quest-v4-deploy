-- READ ONLY. Baseline metadata to compare against an isolated restoration.
-- This does not create a backup, read secret values, or alter production.
select 'public_base_tables' metric,count(*)::bigint total
from information_schema.tables where table_schema='public' and table_type='BASE TABLE'
union all select 'public_functions',count(*)::bigint
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
union all select 'public_rls_tables',count(*)::bigint
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity
union all select 'storage_buckets',count(*)::bigint from storage.buckets
union all select 'storage_object_metadata',count(*)::bigint from storage.objects
union all select 'auth_users',count(*)::bigint from auth.users
union all select 'lesson_schedules',count(*)::bigint from public.cq_v4_lesson_schedule
union all select 'student_submissions',count(*)::bigint from public.cq_v4_student_submissions
order by metric;

-- Bucket-by-bucket file metadata inventory (NOT actual object bytes).
select b.name bucket_name,count(o.id)::bigint object_count,
 coalesce(sum((o.metadata->>'size')::bigint),0)::bigint declared_bytes
from storage.buckets b left join storage.objects o on o.bucket_id=b.id
group by b.id,b.name order by b.name;

-- Schedule data-preservation invariants, without exposing user identifiers.
select count(*)::bigint total_schedules,
 count(*) filter(where released_at is not null)::bigint prearmed_schedules,
 count(distinct (student_user_id,chapter_id))::bigint unique_student_chapters,
 count(*) - count(distinct (student_user_id,lesson_date))::bigint repeated_student_dates
from public.cq_v4_lesson_schedule;

-- Required before any deployment: independent Postgres schema+data dump,
-- Auth recovery drill, actual Storage object-byte backup and restore,
-- Cloudflare deployed-code/config snapshot and rollback rehearsal.
