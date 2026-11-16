# Chapter Quest V4 — production release and rollback checklist (2026-11-16)

**Status:** REVIEW ONLY. No production deployment or SQL changes are authorized by this document.

## Verified baseline
- GitHub Actions Free validation #77: all steps passed, including isolated local Supabase Auth/Storage/Edge/learning flow.
- Production project: `ftffxetmqditfqdvzjdd`; PDF Edge Function `cq-v4-pdf-link` currently ACTIVE v1.
- Production `cq_v4_is_released(uuid,uuid)` already checks enrollment, assignment, published activity, PDF readiness, parent release and local lesson date.
- Production `cq_v4_my_lesson_schedule()` currently reports `released_at IS NOT NULL`, which is insufficient for future lesson dates.
- Production Edge Function v1 currently lacks the authoritative release-date RPC guard.

## Exact code rollback snapshots
- `review/rollback-snapshots/20261116-cq-v4-pdf-link-v1.ts` — complete current production Edge Function v1 source.
- `review/rollback-snapshots/20261116-cq_v4_my_lesson_schedule.sql` — exact current schedule SQL function definition.
- `review/rollback-snapshots/20261116-cq_v4_is_released.sql` — exact current authoritative release gate definition (reference; do not alter).

## Proposed production changes — ONLY after explicit user approval
1. Preflight: verify current deployed Edge Function version and hash, SQL definitions, function execute privileges, existing chapter/student schedule records and service availability; compare to snapshots. Stop if drifted.
2. Verify platform-level database backup/PITR availability and Storage recovery plan. Code snapshots are **not** a database or Storage backup.
3. Replace only `cq-v4-pdf-link` Edge Function with the reviewed candidate `review/edge-candidates/cq-v4-pdf-link/index.ts`; preserve `verify_jwt=true`, secrets, function name, storage bucket, and existing response shape.
4. Replace only `public.cq_v4_my_lesson_schedule()` using `review/sql-candidates/cq_v4_my_lesson_schedule_release_guard.sql`; preserve signature, owner, `SECURITY DEFINER`, grants (`anon` denied; `authenticated` allowed), and `search_path`.
5. Verify: future-dated released lessons show `is_released=false`; no signed PDF links for unreleased lessons; valid assigned lesson after local date can access PDF; parent and student screens still load; inspect Edge errors.
6. Only after passing server verification, test on a real Galaxy tablet and mobile browser; mark these as pending until actually verified.

## Risks and containment
- A mismatch in the release gate can deny legitimate students their PDF. Fail-closed behavior is intentional; immediately stop rollout and investigate.
- The candidate Edge Function is based on deployed v1 and **must not** be substituted with the richer local-only test function without a separate feature parity review.
- Signed URLs already issued before deployment may remain valid until their expiration (v1 uses 120 seconds).
- The schedule function is `SECURITY DEFINER`; changing ownership or grants could affect security.
- No table migrations, enrollment changes, student invitations, PDF uploads, deletes, or Cloudflare deployment are in this limited release scope.

## Rollback
1. Restore Edge Function from `review/rollback-snapshots/20261116-cq-v4-pdf-link-v1.ts` with the same JWT setting and secrets.
2. Execute `review/rollback-snapshots/20261116-cq_v4_my_lesson_schedule.sql` to restore the prior SQL function, then confirm owner and grants match preflight.
3. Recheck production function definitions, authenticated access and student schedule response; verify existing PDF files and student records unchanged.
4. Rollback **reintroduces the known lesson-date PDF access gap**. Prefer a corrected forward fix when possible and avoid issuing early links during the rollback window.

## Approval gate
Do not run production writes, merge PR, or deploy Cloudflare until the user explicitly approves the exact production change and rollback scope.
