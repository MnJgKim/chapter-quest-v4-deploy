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
echo 'ATOMIC_SCHEDULER_PARALLEL_ASSERTIONS_PASSED'
