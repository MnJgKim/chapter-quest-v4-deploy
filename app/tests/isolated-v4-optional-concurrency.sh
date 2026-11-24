#!/usr/bin/env bash
set -euo pipefail
[[ "$PGDATABASE" == cq_v4_isolated && "$PGUSER" == postgres && "$PGHOST" == localhost ]] || exit 2
psql -X -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title) VALUES(md5('optional-race-c')::uuid,md5('optional-race-p')::uuid,true,'Optional race');
INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES(md5('optional-race-p')::uuid,md5('optional-race-s')::uuid);
INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(md5('optional-race-c')::uuid,md5('optional-race-s')::uuid);
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash,questions)
SELECT md5('optional-race-a')::uuid,md5('optional-race-p')::uuid,md5('optional-race-c')::uuid,'[0,0,0,0,0,0,0,"Sample"]','race',jsonb_agg('{"kind":"mc","options":["A","B","C"]}'::jsonb)||'[{"kind":"short","text":"Explain"}]'::jsonb FROM generate_series(1,7);
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,approval_id,approval_hash,questions) SELECT chapter_uuid,now(),id,content_hash,questions FROM public.cq_v4_approval_requests WHERE id=md5('optional-race-a')::uuid;
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES(md5('optional-race-p')::uuid,md5('optional-race-s')::uuid,md5('optional-race-c')::uuid,(now() AT TIME ZONE 'Asia/Seoul')::date,now());
INSERT INTO storage.objects(bucket_id,name) VALUES('cq-v4-speaking',(md5('optional-race-s')::uuid)::text||'/'||(md5('optional-race-c')::uuid)::text||'.webm');
SQL
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
PGAPPNAME=optional_race_holder psql -X -v ON_ERROR_STOP=1 <<'SQL' >"$tmp/holder" 2>&1 &
BEGIN;
SELECT public.cq_v4_lock_student_lesson_writes(md5('optional-race-s')::uuid);
SELECT pg_sleep(15);
COMMIT;
SQL
holder=$!
ready=0
for i in $(seq 1 80); do
 if [[ $(psql -XAt -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='optional_race_holder' AND wait_event='PgSleep'") == 1 ]]; then ready=1; break; fi
 sleep .1
done
[[ "$ready" == 1 ]] || { cat "$tmp/holder"; exit 1; }
submit(){
 PGAPPNAME="$1" psql -X -v ON_ERROR_STOP=1 -v payload="$2" <<'SQL'
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',(md5('optional-race-s')::uuid)::text,true);
SELECT * FROM public.cq_v4_submit_answers(md5('optional-race-c')::uuid, :'payload'::jsonb);
COMMIT;
SQL
}
submit optional_race_a '{"readComplete":true,"answers":["0","0","0","0","0","","",""],"essay":"five","speaking":"Test","hasAudio":true}' >"$tmp/a" 2>&1 & a=$!
submit optional_race_b '{"readComplete":true,"answers":["","","","","","","",""],"essay":"zero","speaking":"Test","hasAudio":true}' >"$tmp/b" 2>&1 & b=$!
ready=0
for i in $(seq 1 80); do
 if [[ $(psql -XAt -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('optional_race_a','optional_race_b') AND wait_event_type='Lock' AND wait_event='advisory'") == 2 ]]; then ready=1; break; fi
 sleep .1
done
[[ "$ready" == 1 ]] || { cat "$tmp/"*; exit 1; }
wait "$holder"
wait "$a" || { cat "$tmp/a"; exit 1; }
wait "$b" || { cat "$tmp/b"; exit 1; }
psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $verify$
DECLARE c uuid:=md5('optional-race-c')::uuid; s uuid:=md5('optional-race-s')::uuid; payload jsonb; frozen jsonb; required boolean;
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_student_submissions WHERE chapter_uuid=c AND child_user_id=s)<>1 OR (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots WHERE chapter_uuid=c AND student_user_id=s)<>1 OR (SELECT count(*) FROM public.cq_v4_reread_progress WHERE chapter_uuid=c AND child_user_id=s)<>1 THEN RAISE EXCEPTION 'Duplicate or missing race records'; END IF;
 SELECT answers INTO payload FROM public.cq_v4_student_submissions WHERE chapter_uuid=c AND child_user_id=s;
 SELECT submitted_answers INTO frozen FROM public.cq_v4_immutable_grading_snapshots WHERE chapter_uuid=c AND student_user_id=s;
 SELECT r.required INTO required FROM public.cq_v4_reread_progress r WHERE chapter_uuid=c AND child_user_id=s;
 IF frozen IS DISTINCT FROM payload->'answers' OR NOT (frozen IN ('["0","0","0","0","0","","",""]'::jsonb,'["","","","","","","",""]'::jsonb)) OR required IS DISTINCT FROM (frozen->>0='') THEN RAISE EXCEPTION 'Race winner or reread mismatch'; END IF;
END $verify$;
SQL
echo V4_OPTIONAL_CONCURRENT_SUBMISSION_ASSERTIONS_PASSED
