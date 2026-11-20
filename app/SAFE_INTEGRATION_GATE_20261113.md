# Chapter Quest V4 — Safe integration gate (2026-11-13)

## Scope and preservation
- Working branch: `work/v4-safe-integration-20261113`, based on `review/nov23-readiness-20261111`.
- Do not merge to `main`, deploy Cloudflare, change hosted Supabase schema/data/auth/storage, or enable paid AI without separate approval.
- The existing `english-v3b-test` project is **not empty** and must be preserved. No destructive SQL.
- Never commit API keys, JWTs, service-role keys, or downloaded personal student records.

## Verified read-only facts
- GitHub review branch is 37 commits ahead of `main` (at time of inspection).
- Hosted test Supabase has Chapter Quest and legacy V3D tables with RLS enabled, plus two active Edge Functions: `cq-v4-pdf-parent` and `cq-v4-pdf-link`.
- Supabase development branches: none found.
- Recorded migration: `20261110114235_cq_v4_validate_submission_and_limit_client_table_privileges`.
- These checks do **not** prove that today's Codex-local P0 changes were pushed, or that RLS policies are secure.

## Integration sequence
1. Locate the latest Codex P0 implementation. Compare its commit SHA, files, SQL, RPC signatures, and Worker routes with this branch. Do not assume it exists in GitHub.
2. Run static tests and existing local integration suites from a clean checkout. Record commands, exact counts, failures, and commit SHA.
3. Produce a read-only schema/RPC/Edge compatibility matrix against the hosted project. Identify drift and migration dependencies without applying SQL.
4. Check backup coverage for database, Auth, Storage, Edge Functions, and rollback. A Git commit is not a database backup.
5. Only in a verified isolated local/test environment, test parent login, student invitation/approval, chapter PDF/TXT registration, problem review/publication/assignment, student answers, audio, submission, and feedback.
6. Verify first lesson source and student identity before any actual publication. Candidate: The Knight at Dawn / The Dark Woods, PDF pages 1–11, subject to parent confirmation.
7. Prepare an explicit production change list, risk assessment, rollback plan, and request approval before any operational change.

## Release gates
- [ ] Latest P0 code reconciled with GitHub
- [ ] Clean-checkout tests passing
- [ ] SQL/RPC/RLS compatibility reviewed
- [ ] Independent recoverable backup verified
- [ ] Isolated end-to-end test passing
- [ ] Actual Galaxy tablet/phone acceptance
- [ ] First lesson approved and assigned
- [ ] Explicit production deployment approval

**Current status:** planning and read-only reconnaissance only; no live integration or release claim.
