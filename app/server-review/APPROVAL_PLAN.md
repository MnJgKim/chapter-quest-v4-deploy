> Historical plan, superseded by the 2026-11-11 inspection: the parent role gate, strict answer validation and privilege reduction are already installed. Do not reapply these candidates or their old rollback scripts as part of the current frontend/Worker release. See ../README.md for the current release gates.

# Supabase server repair — approval required before application

Status: source and isolated tests prepared; NOT applied to the live project.

## Requested production changes

1. Replace only `cq-v4-pdf-parent` with `candidate/cq-v4-pdf-parent/index.ts`, keeping JWT verification enabled. After verifying the logged-in identity, the function calls the existing `cq_is_admin()` RPC and requires the boolean result `true` before constructing a privileged service client. Regular registered-parent operations keep the same API contract; other logged-in accounts are denied.
2. Apply `candidate/submit_validation_and_table_privileges.sql`. It replaces only `cq_v4_submit_answers` to require one valid answer per published question, reject blanks/wrong types and invalid multiple-choice indices, and preserve the existing assignment/audio checks and immutable duplicate-submit behavior. It also revokes TRUNCATE/TRIGGER/REFERENCES from anon/authenticated on the four V4 PDF/snapshot tables. SELECT/INSERT/UPDATE used by snapshot backup are retained.

No existing rows are rewritten or deleted. No user accounts, passwords, student mappings, books, PDFs, submissions or recordings are changed by these two operations. The SQL contains future submission INSERT logic as a function definition; applying it does not invoke a student submission.

## Evidence

- The live project has the four new V4 integration tables, 17 client-callable CQ functions (including cq_is_admin), plus one internal legacy synchronization helper, both active PDF Edge Functions, and private original-PDF/audio buckets.
- Read-only database role simulation recognized the registered parent, while an unrelated authenticated identity saw zero chapter/link/submission rows. Direct reads of approval and V4 submission tables were denied.
- Five live anonymous HTTP requests were denied (three read RPCs and two PDF Edge endpoints).
- The old submission function's incomplete-answer acceptance was reproduced in isolated PostgreSQL. The candidate compiles and passes the full 15-check isolated suite, including complete valid submission, unauthorized denial, duplicate preservation, privilege reduction and function rollback.
- The PDF parent role gate passes 10 mocked Edge-handler tests. These reproduce the old missing-gate behavior without writing anything to the live project.
- Existing CQ tables were fingerprinted using counts and row-set hashes; raw learning content was not copied into fixtures.

These checks do not replace a real parent/student browser login or hosted Storage upload test.

## Risks and limits

- A logged-in account absent from `cq_admins` will lose the ability to create PDF chapters. This is the intended parent-only rule; the existing registered parent is recognized by the live helper.
- Partial or malformed submissions accepted by the previous function will now fail validation. Existing submissions are left unchanged.
- Table-level administrative privileges are removed from client roles; normal snapshot CRUD is retained and checked in isolation.
- Replacing an Edge Function takes effect immediately. A runtime compatibility issue could temporarily prevent new PDF registration; this repair does not replace the student PDF-link function or existing stored files.
- Server TXT publication, real AI inference, real microphone/device checks and full hosted account end-to-end tests remain open. The final student-submit UI gate remains locked pending those tests.
- Cloudflare production traffic is outside this approval request and remains on the prior verified version.

## Apply and verify after user approval

1. Recheck the live preimage definitions and verify they still match the captured backups.
2. Check CQ table counts/fingerprints immediately before applying.
3. Deploy the parent Edge Function with `verify_jwt=true` and apply the one reviewed SQL migration.
4. Re-read definitions/privileges, run read-only role/anonymous denial checks, and compare all CQ data fingerprints.
5. If verification fails, restore the previous Edge source from `backup/cq-v4-pdf-parent/index.ts` and the SQL definition/privileges from `backup/rollback_validation_and_privileges.sql`; then verify fingerprints again. Do not clear browser storage or delete records.

## Backup files

- `backup/cq-v4-pdf-parent/index.ts`: exact source retrieved from the live function before changes.
- `backup/cq-v4-pdf-link/index.ts`: exact source of the unchanged student PDF-link function.
- `backup/functions.sql`: captured CQ V4 helper/RPC definitions.
- `backup/submit_answers.sql`: original submission function.
- `backup/rollback_validation_and_privileges.sql`: restore script for the planned SQL changes.
- `fixtures/`: schema-only data used to build isolated synthetic tests; private parent IDs and existing learning rows are excluded.
