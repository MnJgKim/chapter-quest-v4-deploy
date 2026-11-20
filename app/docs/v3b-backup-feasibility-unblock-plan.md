# V3B backup feasibility and unblock plan — REVIEW ONLY

Verified 2026-11-20 using Supabase read-only project metadata and current Supabase documentation.

## Findings
- Production project `english-v3b-test` (`ftffxetmqditfqdvzjdd`) is ACTIVE_HEALTHY, PostgreSQL 17.11, region ap-northeast-1.
- The connected Supabase integration does **not** expose list-backups, download-backup, database-password, plan/billing, or a safe restore-to-isolated-instance operation. `restore_project` is **not** a backup restoration test and MUST NOT be invoked.
- Project plan, available scheduled backups and restore history are **not yet verified**. Do not infer a Free or paid plan from the project name.
- Supabase docs: https://supabase.com/docs/guides/platform/backups — Pro/Team/Enterprise projects have automatic daily backups; Free projects should make off-site logical dumps with Supabase CLI. Physical DB backups contain Storage metadata, **not Storage object bytes**.
- CLI backup and restore guide: https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
- A SQL inventory of function definitions is useful for targeted rollback but is **not** a database backup.

## Practical routes (choose based on verified dashboard plan)
### A. Scheduled backups available
1. In the Supabase dashboard for this project, open Database > Backups > Scheduled.
2. Confirm a recent successful backup timestamp and the supported restore target/retention. Record the metadata without downloading or sharing secrets.
3. If the plan supports a separate **isolated** restore target, test restore there without modifying the production project. Do not click Restore on the live project.
4. Independently preserve Storage object bytes and Cloudflare deployment artifacts.
5. Verify restored tables, RLS, function ACLs, child records and PDF object checksums against a private read-only baseline. Do not expose child data.

### B. No scheduled backups / Free tier
1. Use a trusted local computer or private Codespace with Supabase CLI, Docker and the **database connection URL from Dashboard > Connect**. Keep the database password and URL out of Git, chat, shell history, logs and CI artifacts.
2. Verify installed CLI commands with `supabase --help` and `supabase db dump --help`.
3. Use the documented `supabase db dump --db-url ... --role-only`, schema, and `--data-only --use-copy` export modes, with output files in a private, access-controlled directory (never the repository). **Important:** Supabase CLI excludes managed `auth` and `storage` schemas by default, so these three files alone are NOT a complete restorable backup of student authentication, Storage metadata, or all Supabase managed state. Design and separately validate supported exports of managed schemas before claiming full disaster recovery.
4. Confirm all files exist, are non-empty and checksummed; encrypt and keep an off-site copy.
5. Restore the dump to a **disposable, isolated** Postgres/Supabase environment compatible with the source version, checking documented role/schema/data restore order and extension requirements. Never restore into production.
6. Validate table counts, function definitions, RLS, representative private checksums and student submission count. Verify Auth user continuity and Storage metadata separately. Export Storage objects separately (the database dump is insufficient for PDF/audio bytes).
7. If Docker/DB connection or storage export is unavailable, mark this route BLOCKED with the precise missing permission or tool rather than retrying indefinitely.

## Security findings from Supabase advisors (read-only)
- Existing INFO: 7 RLS-enabled tables without policies. Some are deliberately accessed only through privileged RPCs; verify intended API behavior rather than adding blanket policies.
- Existing WARN: 9 anonymous-executable SECURITY DEFINER functions, and 36 authenticated-executable functions; review authorization and business purpose individually. Do **not** revoke production permissions blindly: legacy enrollment/vocabulary flows could break.
- Existing WARN: anonymous-sign-in role policies and leaked-password protection settings; determine actual risk and scope before treating as a deployment blocker.
- Supabase security advisor: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable

## Release gate
- The operator must be able to demonstrate a verified recoverable DB copy and Storage object preservation, or formally choose a narrower accepted recovery objective after reviewing risks.
- Before applying the bundle: verify actual production schema/ACL drift and preserve a separate pre-deploy SQL inventory.
- For a bad deployment after new submissions, prefer the documented **non-destructive function rollback** over restoring an old whole-DB snapshot, which could erase submissions after the backup.
- No production SQL, Cloudflare deploy, PR merge, paid upgrade, or new Supabase project without explicit separate approval.

## Smallest remaining human action (only if needed)
Open https://supabase.com/dashboard/project/ftffxetmqditfqdvzjdd/database/backups/scheduled and report whether scheduled backups exist and the most recent successful timestamp (or 'none'). Do not share a password, connection URL, backup content, or API token.

## Confirmed dashboard observation (2026-11-20)
User-provided screenshot of Database Backups > Scheduled backups states: **Free Plan does not include project backups**. Automatic scheduled backup is unavailable. Route B is required; do not request a paid upgrade. Do not treat `supabase db dump`'s default exclusion of managed `auth`/`storage` as full recoverability. Before user runs any command, confirm whether a trusted computer or Codespace has Docker/CLI available and where encrypted private backup files can be retained off-repository.
