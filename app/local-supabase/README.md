# Free local authentication tests

No hosted project or paid resource is used. All identities and learning rows are synthetic.

The standard Supabase CLI 3.1.0 stack was attempted, but its PostgreSQL and Storage images could not extract within this execution environment's 7.9 GB disk limit (`no space left on device`). The failed start was stopped. The schema-only CLI configuration and migration are retained for machines with sufficient space; no production project is linked.

The smaller `lean/` setup uses real official Supabase Auth (GoTrue v2.197.0), PostgREST v16.5 and PostgreSQL 17.11 containers. Only loopback ports are published. It does **not** run the hosted Storage API, Edge runtime or actual AI inference. Its `storage.objects` is a SQL fixture table with the captured policies, so Storage API correctness is not implied.

`lean/prepare.py` generates local-only credentials in an ignored `runtime/` directory without printing them. `lean/setup.py` applies the schema fixture exclusively inside the named local container after Auth is healthy. `lean/integration_test.py` calls fixed loopback URLs and checks real sign-up/login/JWT/REST authorization, publication, submissions and feedback. `lean/browser_test.py` uses three isolated browser contexts against those real local services; hosted requests are blocked. Credentials and account passwords are omitted from reports.

The agent runs setup and commands. For reproduction: prepare the runtime, start `docker compose -f lean/compose.yml up -d`, run `lean/setup.py`, then the integration and browser tests. Keep the root lockfile and pinned image versions. Stop with the same Compose file after tests. Never point this bootstrap or its synthetic fixtures at production; it is not a production migration.

Results: `../qa-results/local-auth.json` (30 checks), `../qa-results/local-auth-browser.json` (9 checks). Existing mock tests continue to cover signed PDF upload, PDF rendering, recording upload failures and lost-response recovery. Actual hosted Storage/Edge tests and real device checks remain release gates.
