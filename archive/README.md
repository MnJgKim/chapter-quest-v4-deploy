# Preserved Codex P0 snapshot — not an active application

`p0-contract-20261113/` preserves all 50 tracked files from local commit
`5f38010274dc734d7bfcf7ef24b3c612c9ccfe7f` byte-for-byte. The integration merge also
retains that entire branch's history. No historical source was discarded.

The active application remains `app/`, based on GitHub branch commit `d58761b`.
Root Wrangler continues to publish only `app/public`. This archive is not a
workspace, build input, operating migration source or alternate deployment.

The archived fresh-project `cq_v4_profiles` schema is different from the preserved
`english-v3b-test` schema (`cq_admins` and existing PDF/activity mappings).
**Never apply the archived SQL/bootstrap or run its deployment helpers against
that existing project.** The paid-model adapter is historical; the active app
keeps AI disabled and supports zero-cost manual/reviewed JSON material.

For optional historical regression checks only, from repository root:
`npm ci --prefix archive/p0-contract-20261113 --ignore-scripts` then
`npm test --prefix archive/p0-contract-20261113`. The snapshot's 49 isolated tests
passed during integration. They do not establish current operating readiness.
