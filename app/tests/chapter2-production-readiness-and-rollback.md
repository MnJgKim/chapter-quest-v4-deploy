# Chapter 2 in-place replacement: production readiness gate (2026-11-20)

Target chapter: `8fe27ea2-b1ce-4404-a5bf-75b5a049a38a`.
Development only. No production DDL/DML or Worker deploy is authorized.

## Verified read-only production baseline
- Chapter: `Chapter 2 : Leaving Again`; PDF ready and verified.
- Storage path: `967982a4-19f9-4a32-a2d5-976f4569091f/8fe27ea2-b1ce-4404-a5bf-75b5a049a38a.pdf`.
- Assignments: 2; submissions: 0; activities: 1; earlier approvals: 1.
- Recheck all values immediately before an approved production transaction.

## Integration test status
- `app/tests/isolated-postgres-chapter2-replacement.sql` creates isolated fixture and asserts authorization, stale hash, malformed MC answer, existing submission, successful replacement, preservation, replay rejection.
- `.github/workflows/chapter2-replacement-isolated.yml` provisions PostgreSQL 16 and runs the fixture.
- **No confirmed GitHub Actions success run/log yet.** Do not mark tests passed.
- Missing: two-session concurrent submission/replacement with actual submission RPC, end-to-end registration/binding, reread feedback gate, UI display.

## Critical concurrency concern
The replacement function locks the PDF chapter row `FOR UPDATE` and checks submissions after acquiring the lock. This conflicts with the FK `KEY SHARE` lock acquired on submission insert. However, the existing submission RPC can read activity/questions **before** the FK lock, then insert after the replacement transaction commits. This can create a submission built from stale content. Before production, update the submission RPC to lock the same chapter row `FOR SHARE` **before** reading activity and validating answers, or introduce an equivalent shared serialization and approval-version check. Test both lock orderings with two real connections. Do not replace the production submit RPC without separate approval.

## Approval registration integration
1. Parent imports `mth_book2_ch2_final_parent_review.json` into the matching local chapter, reviews and explicitly approves.
2. Server registration RPC `cq_v4_register_approval_once` requires a fresh request key and a 10-entry answer-key array; MC positions are numeric and non-MC positions null.
3. Do not call `cq_v4_bind_verified_pdf`: it rejects a chapter already bound to another approval.
4. After production approval and successful isolated tests, call `cq_v4_replace_published_activity` with old approval ID/hash and new approval ID; the function binds the new approval and updates the single activity row transactionally.
5. Existing approval history stays bound to chapter. Existing chapter UUID and assignments stay unchanged.

## Backup before production
Export chapter row, both assignment rows, current activity row, existing approval row, submission and snapshot counts, and all related feedback/reread rows. Record SHA-256 of backup and source PDF; verify restoration to an isolated database. Store backups securely, not in public GitHub. Record new approval request ID and content hash.

## Rollback constraints
If the replacement transaction fails, PostgreSQL rolls back the new binding and activity update. If replacement commits and no student submission exists, a *separately authorized* rollback RPC must restore the previous approved activity while retaining both approval records. If any student submission occurs after replacement, **do not roll back learning content in place**; freeze further submissions and escalate for a historical-data-safe remediation. Never delete old approval or submissions.

## Approval gate
No production authorization requested yet. Require:
- Actual PostgreSQL 16 success log and independent two-connection concurrency test;
- Production-compatible approval registration test and reread/feedback test;
- UI test showing exactly one Chapter 2 and only newly approved questions;
- Backup/restore rehearsal, parent content review and explicit final production approval.
