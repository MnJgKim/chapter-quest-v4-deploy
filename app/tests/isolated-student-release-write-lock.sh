#!/usr/bin/env bash
set -euo pipefail
[[ "${PGDATABASE:-}" == cq_v4_isolated && "${PGHOST:-}" == localhost ]] || exit 2
export PGOPTIONS='-c statement_timeout=10000'
db() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
student=10000000-0000-4000-8000-000000000031
parent=aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa
chapter=20000000-0000-4000-8000-000000000031
other=20000000-0000-4000-8000-000000000032
out=$(mktemp)
ready=$(mktemp)
auto_out=$(mktemp)
rm "$ready"
trap 'wait; rm -f "$out" "$ready" "$auto_out"' EXIT
day=$(db -c "SELECT (now() AT TIME ZONE 'Asia/Seoul')::date")
answers='{"readComplete":true,"answers":["0"],"essay":"Essay","speaking":"Script","hasAudio":true}'

db <<SQL
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('$parent','$student');
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title)
VALUES ('$chapter','$parent',true,'Historical hide'),('$other','$parent',true,'Other chapter');
INSERT INTO public.cq_v4_pdf_assignments VALUES ('$chapter','$student'),('$other','$student');
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions)
SELECT id,now(),'[{"kind":"mc","options":["A","B"]}]' FROM unnest(ARRAY['$chapter','$other']::uuid[]) AS id;
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES ('$parent','$student','$chapter','$day');
INSERT INTO public.cq_v4_student_weekday_policy VALUES ('$student',ARRAY[1,2,3,4,5,6,7],'2020-01-01',true);
INSERT INTO storage.objects(bucket_id,name) VALUES ('cq-v4-speaking','$student/$chapter.webm');
SQL

db -f app/sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql
# Use the normal release predicate rather than any earlier preflight overlay.
db -f app/server-review/release-auth-candidate.sql
rpc() {
  local account=$1 sql=$2
  db <<SQL
SET ROLE authenticated;
SET "request.jwt.claim.sub" = '$account';
$sql
SQL
}
auto="SELECT COALESCE(public.cq_v4_ensure_today_approved_lesson()::text,'NONE');"
toggle="SELECT public.cq_v4_parent_set_lesson_release('$student','$chapter',"
submit="SELECT chapter_uuid FROM public.cq_v4_submit_answers('$chapter','$answers');"
move="SELECT public.cq_v4_parent_schedule_lesson('$student','$chapter','$day'::date + 1);"
[[ $(rpc "$student" "$auto") == NONE ]]
[[ $(db -c "SELECT auto_release_paused FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter'") == t ]]

# Signal after the holder has obtained the lock and issued its state change.
hold() {
  db >"$out" <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '$1';
$2
\! touch "$ready"
SELECT pg_sleep(2);
COMMIT;
SQL
}
wait_ready() {
  for attempt in {1..50}; do
    [[ -f "$ready" ]] && return
    sleep 0.05
  done
  cat "$out" >&2
  return 1
}
reject() {
  local result
  if result=$(rpc "$1" "$2" 2>&1); then
    echo "Unexpected success: $result" >&2
    return 1
  fi
  if [[ "$result" != *"$3"* ]]; then
    echo "$result" >&2
    return 1
  fi
}
rpc "$parent" "${toggle}true);"
hold "$parent" "${toggle}false);" &
holder=$!
wait_ready
rpc "$student" "$auto" >"$auto_out" &
auto_client=$!
reject "$student" "$submit" 'Lesson not released by parent'
wait "$holder"
wait "$auto_client"
[[ $(cat "$auto_out") == NONE ]]
[[ $(rpc "$student" "$auto") == NONE ]]

# A submission in progress wins over both auto-release and a date change.
rm "$ready"
rpc "$parent" "${toggle}true);"
hold "$student" "$submit" &
holder=$!
wait_ready
reject "$parent" "$move" 'Completed lessons cannot be rescheduled'
wait "$holder"
[[ $(rpc "$student" "$auto") == NONE ]]
reject "$parent" "SELECT public.cq_v4_parent_schedule_lesson('$student','$other','$day');" 'Only one chapter'
[[ $(db -c "SELECT count(*) FROM public.cq_v4_student_submissions WHERE child_user_id='$student' AND chapter_uuid='$chapter' AND answers='$answers'::jsonb") == 1 ]]
[[ $(db -c "SELECT lesson_date FROM public.cq_v4_lesson_schedule WHERE chapter_id='$chapter'") == "$day" ]]
echo STUDENT_RELEASE_WRITE_LOCK_ASSERTIONS_PASSED
