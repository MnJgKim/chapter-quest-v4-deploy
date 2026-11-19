#!/usr/bin/env bash
set -euo pipefail
# Two independent PostgreSQL sessions, disposable database only.
student='00000000-0000-0000-0000-000000000002'
psql -v ON_ERROR_STOP=1 -c "BEGIN; SELECT public.cq_v4_lock_student_lesson_writes('$student'::uuid); SELECT pg_sleep(3); COMMIT;" >/tmp/cq-v4-lock-holder.log 2>&1 &
holder=$!
trap 'kill "$holder" 2>/dev/null || true' EXIT
sleep 1
start=$(date +%s)
psql -v ON_ERROR_STOP=1 -c "BEGIN; SELECT public.cq_v4_lock_student_lesson_writes('$student'::uuid); COMMIT;" >/tmp/cq-v4-lock-waiter.log 2>&1
elapsed=$(($(date +%s)-start))
wait "$holder"
trap - EXIT
if ((elapsed < 1)); then
 echo "FAIL: student lock did not block second independent connection" >&2
 exit 1
fi
echo "AUTO_RELEASE_CONCURRENT_STUDENT_LOCK_PASSED elapsed=$elapsed"
