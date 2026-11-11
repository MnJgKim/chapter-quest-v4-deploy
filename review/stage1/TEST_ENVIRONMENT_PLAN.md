# Hosted authentication test plan — approval pending

The user has no separate test accounts. Existing production accounts and student data must never be changed. No hosted test account has been created.

## Proposed isolated environment

Create one temporary Supabase development branch of `english-v3b-test`, named `cq-v4-isolated-qa-20261111`, in the organization selected by the user. Supabase branching supplies a fresh database without copying production rows. There are currently no existing branches.

Before creating it, retrieve the selected organization's branch price and obtain agreement to the quoted cost. The branch must not be merged or rebased into production. Record the returned branch project ref; abort every setup/test request whose target is the production ref `ftffxetmqditfqdvzjdd`.

1. Inspect the branch's schemas and row counts. If migrations do not reproduce the current production functions and policies, install the captured schema/function/Edge sources **only on the branch**. Copy schema and executable code only, never production Auth users, student rows, snapshots, PDFs or recordings. Confirm branch application/Auth/Storage tables contain no production records before adding fixtures.
2. Generate new random parent/student identities and strong random passwords in the test process. Create these identities through the branch's supported Auth Admin API, with test-only addresses and confirmation handled by the admin API. Do not insert or modify `auth.users` using SQL. Do not print credentials or put them in the repository, chat, test reports or browser storage.
3. Add only the newly created branch parent to the branch's `cq_admins`. Test invitation claim and explicit parent approval through the same public APIs as the app. Use a third test-only account for access-denial checks.
4. Configure an isolated local/preview app to use **only the branch URL/public key**, keeping existing user browsers and localStorage/IndexedDB untouched. Register a generated synthetic PDF, publish synthetic activities, record/upload test audio, submit and release feedback. Verify unassigned-account denial, hidden answer keys, expired-session refresh and recovery from a lost response.
5. Verify actual Workers AI inference separately through a non-production authenticated preview after the correct Cloudflare account and usage costs are confirmed. Review question quality and all answers; no synthetic lesson is assigned to real students.
6. Save sanitized results. Remove the temporary branch after the agreed test window (target: same day) to stop ongoing charges, if the branch lifecycle approval includes teardown. Otherwise pause and request that separate teardown approval. Do not delete or revoke any production identity, session, row or object.

## Required secure access

Branch Auth Admin setup needs a branch-scoped secret in the execution environment, or an authenticated Supabase Dashboard session. Cloudflare inference/preview needs an authenticated Cloudflare environment. The agent will perform setup and commands. The user must not send passwords or API tokens in chat.

## Approval scope to present after pricing

Request approval for the quoted-cost temporary branch, new synthetic identities/data confined to that branch, branch-only schema/Edge setup and its agreed teardown. This is separate from production deployment approval. Production remains unchanged throughout. If branch creation or the required secure access is unavailable, retain the completed mock/isolated tests and report hosted authentication as unverified; do not substitute real production users.
