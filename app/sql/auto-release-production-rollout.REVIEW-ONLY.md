# Chapter Quest V4 auto-release production rollout — REVIEW ONLY

**Not approved for deployment.** This document is an operational runbook, not a command to run against production. First lessons on 2026-11-23 (Seowoo) and 2026-11-24 (Seojin) already have manual schedules with released_at set. Preserve that path.

## Read-only preflight
- Confirm current branch/commit and CI status; require a successful disposable PostgreSQL installation and regression run.
- Export and securely retain exact `pg_get_functiondef` for functions to be replaced: `cq_v4_parent_schedule_lesson`, `cq_v4_parent_set_lesson_release`, `cq_v4_submit_answers`; record grants, policies and trigger definitions.
- Back up schema and data for `cq_v4_lesson_schedule`, `cq_v4_student_submissions`, `cq_v4_pdf_chapters`, `cq_v4_pdf_assignments`, `cq_v4_pdf_enrollments`, `cq_v4_activities`, `cq_v4_approval_requests`, `cq_v4_snapshots`, and storage object metadata; verify restorable backup and file access.
- Check table/column constraints, current grants, function ownership, duplicate student/date schedules, active students' authenticated IDs, and existing published approval hashes.
- Verify actual Storage objects and authenticated student PDF reads, not merely `pdf_ready`.

## Proposed migration order (after explicit approval ONLY)
1. Stop new schedule/submission writes during a short controlled window, or use a tested coordinated migration transaction.
2. Create weekday policy and approved queue schema/RPCs from `student-weekday-policy-and-approved-queue.REVIEW-ONLY.sql`.
3. Install auto-release/lock/trigger and replacement schedule/submission RPCs from `student-auto-release-existing-schedule.REVIEW-ONLY.sql`.
4. Review existing scripts' separate BEGIN/COMMIT wrappers: they are **not one atomic migration** as currently authored. Produce and test a single transactional deployment script before production.
5. Verify all grants, RLS, function owner and return signatures. Do not seed unknown student IDs.
6. Configure verified students' weekday policies (Seowoo [1,3,4], Seojin [2,3,5]) and explicitly approved chapter queues only after parent review. Existing released schedules take precedence.
7. Test authenticated student reads and parent controls; compare row counts/checksums and ensure existing submissions and published content are unchanged.

## Rollback
- If the transaction fails before COMMIT, ROLLBACK and confirm no schema/data change.
- If committed, pause new writes, take an incident snapshot, restore exact previous RPC definitions/grants/trigger behavior and previous schedule schema semantics from verified backup. Do not DROP the new column blindly: first inspect manual hides recorded since deployment.
- Do not delete queue/policy data or overwrite student submissions without a separately approved, tested data restoration plan.
- Recheck original manual release for both first lessons; reopen writes only after smoke tests.

## Go/no-go
NO-GO until disposable PostgreSQL integration tests and concurrency tests pass, backup restore is tested, approved source content and storage are verified, and user explicitly approves production changes.
