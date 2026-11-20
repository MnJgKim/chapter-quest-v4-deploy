# Reread warning release gate — evidence and rollback

## Verified on 2026-11-20
- Production read-only function catalog: `cq_v4_parent_submissions` exists, `cq_v4_release_feedback` exists, `cq_v4_parent_lesson` absent.
- Parent JS originally attempted `cq_v4_parent_lesson`, then used local lesson context on failure. Development branch now shows explicit `재독서 판정 보류` when server context is unscorable and no longer trusts local fallback.
- Added development-only parent-authorized `cq_v4_parent_lesson` RPC and PostgreSQL 16 fixture with owner/other-parent/hash/published-content guards.
- Added Node test for 4/7 warning vs 5/7 no-warning, malformed keys, missing answers, and missing context.
- Added GitHub Actions workflow `reread-parent-warning-isolated.yml` for both tests.

## Unverified gates (DO NOT CLAIM RELEASE READY)
1. GitHub Actions run ID, passing PostgreSQL 16 log and Node log not obtained. Commit-status connector cannot confirm push workflow runs.
2. Browser access to deployed Worker was unavailable in current execution environment. No actual parent login, submission-detail warning, tablet/mobile or server RPC call validated.
3. Production RPC is missing. Its installation is a separate **production SQL mutation**, not authorized by development-direction approval.
4. Current production feedback RPC does not implement the reread completion gate. Warning-only release must not claim server enforcement.

## Release plan, subject to separate explicit approval
1. Record current deployed Worker revision and download exact existing assets/configuration; do not deploy without verified rollback artifact.
2. Run and archive passing isolated CI logs. Test parent-only RPC with a test account in nonproduction and confirm no keys leak to student.
3. Separately approve installation of `development-parent-lesson-context-not-for-production.sql` after reviewed migration and rollback; installation is a production change.
4. Separately approve Worker deploy of parent UI changes after staging build and authenticated browser checks.
5. After deployment verify parent submitted lesson shows 4/7 warning, 5/7 no warning, missing/mismatch shows `재독서 판정 보류`, and student UI does not receive answer keys.
6. Rollback: restore previous Worker revision/assets; if approved and safe, revoke/drop only the newly installed parent lesson RPC after checking dependencies. Never touch submissions, approvals, PDF, assignments or snapshots.

## Scope isolation
Magic Tree House #2 Chapter 2 correction is deferred; do not change it as part of reread warning rollout.
