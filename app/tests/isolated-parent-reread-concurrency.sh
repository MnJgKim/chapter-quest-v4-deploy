#!/usr/bin/env bash
set -euo pipefail
# CI-only: disposable PostgreSQL 16; never run on production.
if [[ "$PGDATABASE" != "cq_v4_isolated" || "$PGUSER" != "postgres" ]]; then
 echo "Refusing non-isolated database" >&2; exit 2
fi
psql -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER TABLE public.cq_v4_student_submissions ADD COLUMN IF NOT EXISTS feedback_released boolean NOT NULL DEFAULT false;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text);
\i review/sql-candidates/cq_v4_parent_reread_notices.REVIEW-ONLY.sql
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title) VALUES('cccccccc-cccc-4ccc-cccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','Concurrent fixture');
INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES('cccccccc-cccc-4ccc-cccc-cccccccccccc','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,approval_id,approval_hash,questions) VALUES('cccccccc-cccc-4ccc-cccc-cccccccccccc',now(),'dddddddd-dddd-4ddd-dddd-dddddddddddd','hash-concurrent',(SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('a','b'))) FROM generate_series(1,10)));
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash) VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-cccc-cccccccccccc','[0,0,0,0,0,0,0,0,0,0]'::jsonb,'hash-concurrent');
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES('cccccccc-cccc-4ccc-cccc-cccccccccccc','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{"answers":["0","0","0","0","0","0","1","1","1","1"]}'::jsonb);
SQL
run_one() {
 psql -X -v ON_ERROR_STOP=1 -At <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true);
SELECT correct_mc||'/'||total_mc FROM public.cq_v4_parent_sync_reread_notice('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-cccc-cccccccccccc');
COMMIT;
SQL
}
run_one > /tmp/cq-reread-a.log 2>&1 & pid_a=$!
run_one > /tmp/cq-reread-b.log 2>&1 & pid_b=$!
wait "$pid_a"; wait "$pid_b"
grep -q '6/10' /tmp/cq-reread-a.log
grep -q '6/10' /tmp/cq-reread-b.log
count="$(psql -X -v ON_ERROR_STOP=1 -At -c "SELECT count(*) FROM public.cq_v4_reread_notices WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb' AND chapter_uuid='cccccccc-cccc-4ccc-cccc-cccccccccccc'")"
if [[ "$count" != 1 ]]; then echo "Expected one notice, got $count" >&2; exit 1; fi
echo "PARENT_REREAD_CONCURRENT_UNIQUE_NOTICE_PASSED"
