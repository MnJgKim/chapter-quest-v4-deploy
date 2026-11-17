# Hosted first lessons — verified behavior and safe release plan (2026-11-17)

## Verified read-only facts
- Active project: english-v3b-test (project ref ftffxetmqditfqdvzjdd).
- 11 scheduled rows, two student user IDs, one parent ID.
- All 11 schedule rows match an enrollment; 10 do not match a currently approved, unrevoked invite.
- An approved invite named 서진 is claimed and enrolled, but has no scheduled lessons.
- No approved invite named 서우 was found. Never infer that an unlabelled account is 서우.
- One 2026-11-23 row has PDF ready/verified, activity published, assignment, enrollment, released_at; its identity is unverified.
- No 2026-11-24 schedule row.
- The live cq_v4_is_released function requires released_at IS NOT NULL and Seoul-local current date >= lesson_date, plus PDF, activity, assignment, enrollment and student/parent authorization. Thus *date-based student visibility is already server-enforced for pre-approved schedules*; a new Cron job is not required for that part. This is not evidence that future lesson creation is automatic.

## Mandatory blockers
1. Identify 서우 via authenticated approval flow; do not reassign existing 10 records based on dates.
2. Confirm source chapter, PDF and published activity for 서진 and authorize her schedule for 2026-11-24.
3. Prepare separate Wednesday lesson content. The existing 10 scheduled chapters are already published; don't silently move their dates or duplicate chapter IDs.
4. Run live student account/device tests and confirm the student RPC returns only lessons released on or before the local date.
5. Verify backups and restore in isolation before requesting final approval for any production changes.

## Predeployment safety
- Preserve 11 schedule rows, current invite/enrollment/assignment rows, PDF Storage and student submissions.
- Read-only snapshots and counts are not a verified recoverable backup. Confirm a usable backup plus a restore drill.
- Existing cq_v4_parent_schedule_lesson uses ON CONFLICT UPDATE: avoid it for any existing student/chapter without an explicit collision-free check and final approval.
- No deployment, production write, PR merge, or release RPC invocation was performed.
