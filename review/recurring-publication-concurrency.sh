#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == cq_v4_recurring_test && "${PGHOST:-}" == localhost ]] || exit 2
export PGOPTIONS='-c statement_timeout=10000'
psql_safe() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
student=10000000-0000-4000-8000-000000000091
parent=aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa
chapter=20000000-0000-4000-8000-000000000091
out=$(mktemp)
ready=$(mktemp)
rm "$ready"
trap 'wait; rm -f "$out" "$ready"' EXIT
psql_safe <<SQL
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('$parent','$student');
INSERT INTO public.cq_v4_student_weekday_policy VALUES ('$student',ARRAY[1,2,3,4,5,6,7],'2026-01-01',true);
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title,pdf_verified_at,storage_path)
VALUES ('$chapter','$parent',true,'Concurrent fixture',now(),'fixture.pdf');
INSERT INTO public.cq_v4_approval_requests VALUES
 ('$chapter','$parent','$chapter','fixture','Source','hash','[{"kind":"short","text":"Question"}]',
  '["Answer"]','[{"word":"a","meaning":"b"}]','Write','Speak');
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$parent';
SELECT public.cq_v4_parent_enqueue_approved('$chapter',ARRAY['$student']::uuid[],1);
SQL
psql_safe >"$out" <<SQL &
BEGIN;
SELECT public.cq_v4_run_recurring_releases();
\! touch "$ready"
SELECT pg_sleep(1);
COMMIT;
SQL
worker=$!
for attempt in {1..50}; do
  [[ -f "$ready" ]] && break
  sleep 0.05
done
[[ -f "$ready" ]]
result=$(psql_safe <<SQL
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$student';
SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NONE');
SQL
)
wait "$worker"
[[ "$result" == NONE && $(head -1 "$out") == 1 ]]
[[ $(psql_safe -c "SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id='$student' AND released_at IS NOT NULL") == 1 ]]
[[ $(psql_safe -c "SELECT count(*) FROM public.cq_v4_pdf_assignments WHERE student_user_id='$student'") == 1 ]]
echo RECURRING_CRON_STUDENT_RACE_PASSED
