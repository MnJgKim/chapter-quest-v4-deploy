#!/usr/bin/env bash
# Isolated PostgreSQL 16 CI only. Never set PGHOST/PGDATABASE to Supabase.
set -euo pipefail
if [[ "${PGDATABASE:-}" != 'cq_v4_isolated' || "${PGHOST:-}" != 'localhost' ]]; then
  echo 'Refusing to run outside local cq_v4_isolated PostgreSQL' >&2; exit 2
fi
export PGOPTIONS='-c statement_timeout=12000'
student='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'
chapter='99999999-9999-4999-8999-999999999999'
parent='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
cleanup() {
  psql -X -v ON_ERROR_STOP=1 -q <<SQL
DELETE FROM public.cq_v4_student_submissions WHERE chapter_uuid='$chapter';
DELETE FROM storage.objects WHERE bucket_id='cq-v4-speaking' AND name='$student/$chapter.webm';
DELETE FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter';
DELETE FROM public.cq_v4_approved_chapter_queue WHERE chapter_id='$chapter';
DELETE FROM public.cq_v4_student_weekday_policy WHERE student_user_id='$student';
DELETE FROM public.cq_v4_pdf_assignments WHERE chapter_id='$chapter';
DELETE FROM public.cq_v4_activities WHERE chapter_uuid='$chapter';
DELETE FROM public.cq_v4_pdf_enrollments WHERE student_user_id='$student';
DELETE FROM public.cq_v4_pdf_chapters WHERE chapter_id='$chapter';
SQL
}
trap cleanup EXIT
psql -X -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO public.cq_v4_pdf_chapters VALUES('$chapter','$parent',true,'Concurrent chapter');
INSERT INTO public.cq_v4_pdf_assignments VALUES('$chapter','$student');
INSERT INTO public.cq_v4_pdf_enrollments VALUES('$parent','$student');
INSERT INTO public.cq_v4_activities VALUES('$chapter',now(),'[]');
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal)
VALUES('$parent','$student','$chapter',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES('$student',ARRAY[1,2,3,4,5,6,7],DATE '2020-01-01');
SQL
first=$(mktemp); second=$(mktemp)
trap 'rm -f "$first" "$second"; cleanup' EXIT
# Ensure all background sessions are reaped before deleting fixtures on failure.
wait_for_children() {
  for pid in "${pid_a:-}" "${pid_b:-}"; do
    if [[ -n "$pid" ]]; then wait "$pid" 2>/dev/null || true; fi
  done
}
trap 'wait_for_children; rm -f "$first" "$second"; cleanup' EXIT
# Session A holds the student/day lock before scheduling. Session B must wait.
psql -X -At -v ON_ERROR_STOP=1 >"$first" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$student',true);
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('cq_v4_day:$student:' || (now() AT TIME ZONE 'Asia/Seoul')::date::text,0));
SELECT pg_sleep(2);
SELECT public.cq_v4_ensure_today_approved_lesson();
COMMIT;
SQL
pid_a=$!
sleep 0.4
psql -X -At -v ON_ERROR_STOP=1 >"$second" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$student',true);
SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NULL');
COMMIT;
SQL
pid_b=$!
wait "$pid_a"
wait "$pid_b"
if ! grep -Fq "$chapter" "$first"; then
  echo 'Concurrent scheduler A failed to create first slot' >&2; exit 1
fi
if ! grep -Fxq 'NULL' "$second"; then
  echo 'Concurrent scheduler B created or returned a duplicate slot' >&2; exit 1
fi
count=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter'")
if [[ "$count" != '1' ]]; then echo "Unexpected concurrent schedule count: $count" >&2; exit 1; fi
# Parent scheduling wins the same day lock; student must not add a second slot.
psql -X -v ON_ERROR_STOP=1 -q -c "DELETE FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter'"
psql -X -At -v ON_ERROR_STOP=1 >"$first" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$parent',true);
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('cq_v4_day:$student:' || (now() AT TIME ZONE 'Asia/Seoul')::date::text,0));
SELECT pg_sleep(2);
SELECT public.cq_v4_parent_schedule_lesson('$student','$chapter',(now() AT TIME ZONE 'Asia/Seoul')::date);
COMMIT;
SQL
pid_a=$!
sleep 0.4
psql -X -At -v ON_ERROR_STOP=1 >"$second" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$student',true);
SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NULL');
COMMIT;
SQL
pid_b=$!
wait "$pid_a"
wait "$pid_b"
if ! grep -Fxq 'NULL' "$second"; then
  echo 'Student created duplicate slot during parent scheduling' >&2; exit 1
fi
count=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter'")
if [[ "$count" != '1' ]]; then echo "Parent/student race schedule count: $count" >&2; exit 1; fi
echo 'PARENT_SCHEDULER_PARALLEL_ASSERTIONS_PASSED'
# Student submission must win the chapter lock and make a concurrent
# parent reschedule fail without mutating the completed lesson.
psql -X -v ON_ERROR_STOP=1 -q <<SQL
UPDATE public.cq_v4_activities
SET questions='[{"kind":"mc","options":["A","B"]}]'::jsonb
WHERE chapter_uuid='$chapter';
INSERT INTO storage.objects(bucket_id,name)
VALUES('cq-v4-speaking','$student/$chapter.webm');
SQL
psql -X -At -v ON_ERROR_STOP=1 >"$first" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$student',true);
SELECT pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('$student:$chapter',0));
SELECT pg_sleep(2);
SELECT chapter_uuid FROM public.cq_v4_submit_answers('$chapter',
 '{"readComplete":true,"answers":["0"],"essay":"Test essay","speaking":"Test script","hasAudio":true}'::jsonb);
COMMIT;
SQL
pid_a=$!
sleep 0.4
# The parent request is expected to be denied after the student commits.
psql -X -At -v ON_ERROR_STOP=1 >"$second" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$parent',true);
SELECT public.cq_v4_parent_schedule_lesson('$student','$chapter',
  (now() AT TIME ZONE 'Asia/Seoul')::date + 1);
COMMIT;
SQL
pid_b=$!
wait "$pid_a"
if wait "$pid_b"; then
  echo 'Parent rescheduled a chapter concurrently submitted by student' >&2; exit 1
fi
if ! grep -Fq 'Completed lessons cannot be rescheduled' "$second"; then
  echo 'Parent request failed for unexpected reason:' >&2; cat "$second" >&2; exit 1
fi
if ! grep -Fq "$chapter" "$first"; then
  echo 'Student submission failed to commit' >&2; exit 1
fi
count=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.cq_v4_student_submissions WHERE chapter_uuid='$chapter' AND child_user_id='$student'")
if [[ "$count" != '1' ]]; then echo 'Student submission not immutable' >&2; exit 1; fi
count=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter' AND lesson_date=(now() AT TIME ZONE 'Asia/Seoul')::date")
if [[ "$count" != '1' ]]; then echo 'Submitted lesson date changed' >&2; exit 1; fi
echo 'SUBMISSION_PARENT_PARALLEL_ASSERTIONS_PASSED'
echo 'ATOMIC_SCHEDULER_PARALLEL_ASSERTIONS_PASSED'
