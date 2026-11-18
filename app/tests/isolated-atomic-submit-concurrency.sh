#!/usr/bin/env bash
set -euo pipefail
# Disposable CI database ONLY. Two independent psql connections compete for one submission.
[[ "${PGDATABASE:-}" == "cq_v4_isolated" && "${PGUSER:-}" == "postgres" ]] || { echo "Refusing non-isolated database" >&2; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SETUP'
\set ON_ERROR_STOP on
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text);
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_submit_with_frozen_snapshot.REVIEW-ONLY.sql
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Approved'),
 ('44444444-4444-4444-8444-444444444444','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Not approved');
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),
 ('44444444-4444-4444-8444-444444444444','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES
 ('33333333-3333-4333-8333-333333333333',now(),'[{"kind":"mc","options":["A","B"]}]'),
 ('44444444-4444-4444-8444-444444444444',now(),'[{"kind":"mc","options":["A","B"]}]');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',(now() AT TIME ZONE 'Asia/Seoul')::date),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444',(now() AT TIME ZONE 'Asia/Seoul')::date);
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',ARRAY[1,2,3,4,5,6,7],DATE '2020-01-01');
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash) VALUES
 ('99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','33333333-3333-4333-8333-333333333333','[0]'::jsonb,'frozen-approved'),
 ('99999999-9999-4999-8999-999999999998','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','44444444-4444-4444-8444-444444444444','[0]'::jsonb,'frozen-approved-2');
UPDATE public.cq_v4_activities SET approval_id='99999999-9999-4999-8999-999999999999',approval_hash='frozen-approved' WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
UPDATE public.cq_v4_activities SET approval_id='99999999-9999-4999-8999-999999999998',approval_hash='frozen-approved-2' WHERE chapter_uuid='44444444-4444-4444-8444-444444444444';

INSERT INTO storage.objects(bucket_id,name) VALUES ('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/33333333-3333-4333-8333-333333333333.webm');
SETUP
submit() {
 local answer="$1"
 psql -X -v ON_ERROR_STOP=1 -At <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["$answer"],"essay":"Concurrent $answer","speaking":"Concurrent","hasAudio":true}'::jsonb);
COMMIT;
SQL
}
submit 0 > /tmp/cq-submit-concurrent-a.log 2>&1 & a=$!
submit 1 > /tmp/cq-submit-concurrent-b.log 2>&1 & b=$!
wait "$a"; wait "$b"
psql -X -v ON_ERROR_STOP=1 -At <<'VERIFY'
DO $verify$
DECLARE n integer; frozen integer; essay text; frozen_answer text;
BEGIN
 SELECT count(*) INTO n FROM public.cq_v4_student_submissions WHERE chapter_uuid='33333333-3333-4333-8333-333333333333' AND child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
 SELECT count(*) INTO frozen FROM public.cq_v4_immutable_grading_snapshots WHERE chapter_uuid='33333333-3333-4333-8333-333333333333' AND student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
 IF n<>1 OR frozen<>1 THEN RAISE EXCEPTION 'Concurrent submit count mismatch: %, %',n,frozen;END IF;
 SELECT answers->>'essay' INTO essay FROM public.cq_v4_student_submissions WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
 SELECT submitted_answers->>0 INTO frozen_answer FROM public.cq_v4_immutable_grading_snapshots WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
 IF (essay='Concurrent 0' AND frozen_answer<>'0') OR (essay='Concurrent 1' AND frozen_answer<>'1') OR essay NOT IN ('Concurrent 0','Concurrent 1')
 THEN RAISE EXCEPTION 'Frozen answer differs from winning submission';END IF;
 RAISE NOTICE 'ATOMIC_CONCURRENT_SUBMISSION_ASSERTIONS_PASSED';
END $verify$;
VERIFY
echo 'ATOMIC_CONCURRENT_SUBMISSION_ASSERTIONS_PASSED'
