#!/usr/bin/env bash
# Use a freshly isolated database or the isolated CI PostgreSQL service.
set -euo pipefail
if [[ "${PGDATABASE:-}" != cq_v4_isolated || "${PGHOST:-}" != localhost ]]; then
  echo 'Refusing to run outside local cq_v4_isolated PostgreSQL' >&2
  exit 2
fi
export PGOPTIONS='-c statement_timeout=12000'
student='10000000-0000-4000-8000-000000000010'
chapter='20000000-0000-4000-8000-000000000010'
parent='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
first=$(mktemp)
second=$(mktemp)
trap 'wait; rm -f "$first" "$second"' EXIT

psql -X -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title)
VALUES ('$chapter','$parent',true,'Concurrent release');
INSERT INTO public.cq_v4_pdf_assignments VALUES ('$chapter','$student');
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('$parent','$student');
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions)
VALUES ('$chapter',now(),'[]');
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal)
VALUES ('$parent','$student','$chapter',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('$student',ARRAY[1,2,3,4,5,6,7],'2026-01-01');
SQL

# Keep the first release uncommitted so the other authenticated call competes.
psql -X -v ON_ERROR_STOP=1 -qAt >"$first" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '$student';
SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NONE');
SELECT pg_sleep(1);
COMMIT;
SQL
a=$!
psql -X -v ON_ERROR_STOP=1 -qAt >"$second" <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '$student';
SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NONE');
SELECT pg_sleep(1);
COMMIT;
SQL
b=$!
wait "$a"
wait "$b"
[[ $(cat "$first" "$second" | sed '/^$/d' | sort) == $(printf '%s\nNONE' "$chapter") ]]
[[ $(psql -X -v ON_ERROR_STOP=1 -qAt -c "SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id='$student' AND released_at IS NOT NULL") == 1 ]]

# Exercise the hosted predicate with the release flag produced by the RPC.
[[ $(psql -X -v ON_ERROR_STOP=1 -qAt <<SQL
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$student';
SELECT public.cq_v4_is_released('$chapter','$student');
SQL
) == t ]]
echo 'STUDENT_WEEKDAY_RELEASE_CONCURRENCY_PASSED'
