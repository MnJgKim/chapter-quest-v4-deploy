# Chapter Quest V4 — automatic weekday release / deployment preflight (2026-11-18)

STATUS: REVIEW ONLY. No production change, deployment, PR merge, student assignment or student-data mutation authorized.

## Confirmed from current source and read-only production function definitions
- Student client app/public/js/student-api.js calls cq_v4_ensure_today_approved_lesson but suppresses only a recognized 404 function-not-found response; it then requests cq_v4_my_released_chapters.
- Production cq_v4_is_released requires BOTH released_at IS NOT NULL and Asia/Seoul current date >= lesson_date, plus published activity, ready PDF, assignment, enrollment and authorized identity.
- Production cq_v4_parent_set_lesson_release is a parent-only manual toggle of released_at. cq_v4_parent_schedule_lesson is a parent-only manual lesson_date update.
- app/sql/student-weekday-policy-v1.REVIEW-ONLY.sql defines only a policy table; app/sql/student-weekday-next-date-v1.REVIEW-ONLY.sql defines only a pure date helper. Neither selects an approved chapter nor releases it.
- The optional scheduler RPC was previously found absent in production; a fresh recheck is needed before release.
- Current student app only shows chapters authorized by the server; client-side weekday UI is not an access-control substitute.
- CI run 44245647393 passed. Existing PDF, audio, submission and tablet-login successes are NOT to be repeated without a code change affecting them.

## Blocking release invariant
A configured weekday must automatically expose the *next parent-approved, pre-assigned* lesson on its approved date without manual released_at intervention. Do not select chapters by UUID or release unapproved/unassigned lessons. Preserve prior immutable submissions, explicit makeup dates, existing Chapter 1–10 schedule and student records.

## Minimal change candidate (not yet implemented or approved)
1. Review isolated SQL scheduler transaction and weekday policy with owner-approved identity mappings. Never use a new policy table to automatically assign lessons.
2. In isolated PostgreSQL, test authenticated student scope, enrollment/assignment/approved snapshot, concurrent calls, Asia/Seoul midnight, idempotency, existing releases, explicit makeup dates and refusal of future/other-student release.
3. Make the server RPC available only after review and explicit production authorization; remove the missing-function fallback only when production compatibility is established.
4. Review parent manual release UI: either restrict manual override to authorized makeup/recovery or clearly separate it from normal weekday operation. Never allow client-only weekday authorization.
5. Compare deployed Cloudflare static asset hashes and Worker version against development candidates before choosing exact files. main is NOT a deployed baseline.

## Current deployment/rollback blocker
- Cloudflare account deployment version, Worker source/config, and deployed asset manifest/hash are not available from the current connected tools. Public URL fetch was attempted but unavailable in this environment. GitHub CI run 44245647393 has no artifacts.
- A GitHub source archive is not proof of a deployed Worker backup.
- Do not request deployment approval until a Cloudflare read-only export or authenticated version inventory supplies deployed version, asset hashes, configuration (without secrets), and a restorable previous version.
- Dry-run build is not a rollback test. Rollback must restore prior Worker revision/static assets without changing Supabase or student records.

## No-repeat rule
Do not repeat passed CI, tablet login, PDF, audio or submission checks. Run only new scheduler and release-invariant tests, plus release-specific smoke checks after explicit deployment approval.

## Candidate handoff

Install the reviewed weekday policy and approved queue before
`student-auto-release-existing-schedule.REVIEW-ONLY.sql`. The student transport
already calls the scheduler, then the hosted released-list RPC. The scheduler
sets the existing release flag on the first student request on or after Seoul
midnight of an eligible date. It preserves explicit dates and falls back to
the approved ordinal queue only when there is no reserved slot or unfinished
earlier scheduled lesson. Off-pattern manual releases keep the existing date
gate. A parent hide made after installation pauses automatic release.

Before activation, verify the exact student and parent account IDs through the
approved identity and enrollment records. The repository audit prefix is not a
configuration value. As part of the authorized rollout, configure those verified
student IDs using `student-weekday-policy-initial-config.REVIEW-ONLY.sql` with ISO weekdays
`ARRAY[1,3,4]` for 서우 and `ARRAY[2,3,5]` for 서진 and an agreed Seoul
effective date. Review any existing policy rows before activation because the initial
configuration preserves them. Leave 시우 without an enabled row until their policy is approved.
Populate the queue only from explicit approval and pre-existing assignments.
Keep 서진's queue and schedule empty until her PDF and assignment are approved.

The captured hosted parent scheduler does not take the shared student/day and
student/chapter locks. Reconcile and validate all hosted schedule writers and
the submit RPC against that lock order before enabling this candidate. Existing
null release flags do not reveal whether the parent previously hid a lesson.
Review any such holds before enabling the policy. No production policy, queue,
schedule, or deployment is changed by this branch.
