#!/usr/bin/env bash
# Isolated two-connection lock ordering check; NOT full submission RPC test.
set -euo pipefail
export PGPASSWORD=postgres
PSQL=(psql -X -h 127.0.0.1 -U postgres -d chapter2_test -v ON_ERROR_STOP=1 -At)
CHAPTER=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# Setup fixture must already be present; use separate transactions.
# Scenario A: submission's SHARE lock first; replacement UPDATE waits.
("${PSQL[@]}" -c "BEGIN; SELECT 1 FROM public.cq_v4_pdf_chapters WHERE chapter_id='$CHAPTER' FOR SHARE; SELECT pg_sleep(2); COMMIT;" >/tmp/cq-a-reader.log) &
reader=$!
sleep 0.4
start=$(date +%s)
"${PSQL[@]}" -c "BEGIN; SELECT 1 FROM public.cq_v4_pdf_chapters WHERE chapter_id='$CHAPTER' FOR UPDATE; ROLLBACK;" >/tmp/cq-a-writer.log
elapsed=$(( $(date +%s) - start ))
wait "$reader"
if (( elapsed < 1 )); then echo "SHARE_FIRST_LOCK_ASSERTION_FAILED"; exit 1; fi
echo "SHARE_FIRST_LOCK_ASSERTION_PASSED"
# Scenario B: replacement UPDATE lock first; submission SHARE waits.
("${PSQL[@]}" -c "BEGIN; SELECT 1 FROM public.cq_v4_pdf_chapters WHERE chapter_id='$CHAPTER' FOR UPDATE; SELECT pg_sleep(2); ROLLBACK;" >/tmp/cq-b-writer.log) &
writer=$!
sleep 0.4
start=$(date +%s)
"${PSQL[@]}" -c "BEGIN; SELECT 1 FROM public.cq_v4_pdf_chapters WHERE chapter_id='$CHAPTER' FOR SHARE; ROLLBACK;" >/tmp/cq-b-reader.log
elapsed=$(( $(date +%s) - start ))
wait "$writer"
if (( elapsed < 1 )); then echo "UPDATE_FIRST_LOCK_ASSERTION_FAILED"; exit 1; fi
echo "UPDATE_FIRST_LOCK_ASSERTION_PASSED"
