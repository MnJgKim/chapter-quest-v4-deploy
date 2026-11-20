# P0 server contract — 2026-11-13

For the implemented AI/TXT/approval/session continuation, see [P0-AI-TEXT-SESSIONS.md](P0-AI-TEXT-SESSIONS.md). The baseline contract below is retained; the continuation adds one migration and a reading RPC.

This branch is a candidate for a **new local/test project**, not a migration plan for the unknown existing production schema. Nothing here has been applied to a remote project. The original ZIP is retained unchanged; `public/`, `wrangler.jsonc` and `README.txt` were extracted from it before the targeted client edits.

## Identity and first parent

- Supabase Auth `auth.users.id` is the only account identity. Display names never authorize access.
- The signup trigger creates `cq_v4_profiles(role='student')`; user metadata cannot assign parent privileges. Authenticated clients cannot edit profiles.
- For a **new test project**, a trusted administrator creates a parent Auth user and explicitly inserts/updates its profile to `parent`. There is no public parent enrollment endpoint. For an Auth user created before migration, insert its profile first. Do not run this bootstrap on production as part of this task.
- Example template for the TEST database only (replace the identifier, not a secret):

```sql
insert into public.cq_v4_profiles(user_id, role)
values ('<TEST_PARENT_AUTH_USER_UUID>'::uuid, 'parent')
on conflict (user_id) do update set role = excluded.role;
```

### Account issuance and student approval

1. Parent signs in using the existing cloud panel, then enters the student's email.
2. `cq-v4-student-account` validates the user's JWT through Auth `/user`, verifies the database parent role and reserves a quota (10 requests/parent/hour).
3. Auth Admin `/invite` sends an email invitation. The service key exists only in Edge environment settings. A successful response means invitation requested, not mail delivered.
4. The student follows the invitation, sets a password (12+ characters), and then signs in through the existing student panel. The callback token is removed from the address bar **before external PDF scripts load**, kept in a closure and never persisted.
5. Parent issues a separate 48-hex one-time relationship code. It expires in 15 minutes. Only a hash is stored; at most 20 codes/parent/15 minutes.
6. The student claims the code; the relation remains `active=false`. Only that parent can approve/reactivate it. A new claim never silently reactivates a revoked relationship.
7. Approval supplies access only to explicitly assigned, published, PDF-ready chapters.

Auth email invitations and parent relationship codes have different lifetimes and purposes. Mail delivery, redirect allowlists, existing-email behavior and actual hosted Auth callbacks still require a disposable Supabase test project. The UI does not implement self-signup or public parent elevation.

## Single chapter identity

```
(parent Auth UUID, local book.id, local chapter.id)
                     -> cq_v4_chapters.chapter_uuid
                     -> PDF object, approval, assignments, submissions
```

- `UNIQUE(parent_user_id, book_id, chapter_id)` is the canonical mapping. A second parent using the same local IDs gets a different UUID.
- Local selected IDs are sent both to PDF `create_chapter` and existing `cq_v4_register_approval_once`. A manually typed PDF title cannot choose a different identity.
- All paths use the existing `cq_v4_child_access` relationship. There is no PDF-specific student relationship table.
- Work in this order: choose local book/chapter -> upload/verify server PDF -> approve local material -> select approved students -> publish.
- Original PDF path: `cq-v4-originals/<parent_uuid>/<chapter_uuid>/original.pdf`.
- Speaking path: `cq-v4-speaking/<student_uuid>/<chapter_uuid>.<webm|mp4|ogg>`.
- A verified PDF is immutable in this milestone. A published chapter cannot switch to a different approval. Revised content needs a new local chapter ID; version editing is future work. This intentionally avoids altering materials under existing submissions.

## Database RPC compatibility

| RPC | Caller | Contract |
| --- | --- | --- |
| `cq_v4_my_role()` | authenticated | `parent`, `student` or null |
| `cq_v4_issue_invite()` | parent | one-time plaintext token |
| `cq_v4_claim_invite(p_token,p_student_name)` | student | boolean; inactive relation |
| `cq_v4_approve_child / cq_v4_revoke_child(p_child_user_id)` | owning parent | boolean |
| `cq_v4_register_approval_once(...)` | parent | approval UUID; same request key + exact payload returns same UUID; changed payload rejected |
| `cq_v4_publish_approved(p_approval_id,p_children)` | parent | canonical chapter UUID; atomic idempotent assignment, requires ready PDF and approved children |
| `cq_v4_publication_status(p_approval_id,p_children)` | parent | content_matches, all_assigned, missing_children, chapter_uuid |
| `cq_v4_parent_pdf(p_action,p_args)` | parent | metadata only; list/create/upload path/inspect/assign/unassign |
| `cq_v4_finalize_pdf(p_chapter_uuid,p_parent_user_id)` | service role only | used only after Edge PDF signature verification |
| `cq_v4_pdf_access(p_chapter_uuid)` | assigned student | object path, otherwise denied |
| `cq_v4_my_chapters()` | student | assigned published chapters, **no source or answer key** |
| `cq_v4_my_chapter_activities(p_chapter_uuid)` | student | vocabulary and writing/speaking prompts |
| `cq_v4_my_submission(p_chapter_uuid)` | student | own submission; unreleased feedback omitted |
| `cq_v4_submit_answers(p_chapter_uuid,p_answers)` | student | immutable insertion; validates required answers and server audio object |
| `cq_v4_parent_submissions()` | parent | own chapters' submissions |
| `cq_v4_release_feedback(...)` | owning parent | feedback update/release |
| `cq_v4_reserve_account_invite(p_email)` | parent | quota reservation before email request |

Submission/feedback RPCs support existing client contracts and database tests. **The student final-submit UI is deliberately still disabled** pending the next P0 validation milestone. This branch does not declare the whole learning workflow ready.

`cq_private.approvals` holds immutable material snapshots and answer keys. Browser roles have no schema usage, table grants or helper execute privileges. Public RPCs use a fixed empty search_path, explicit Auth identity/role checks and owner/assignment predicates. Student-facing question objects accept only kind/text/options.

Direct REST is limited to parent-owned snapshots and parent-owned child relation SELECT. Chapter/assignment/profile writes go through authorized RPCs. Snapshot timestamps implement the existing optimistic concurrency contract; snapshots do not back up binary files or implement realtime merge.

## Edge HTTP contracts

All functions require a verified Bearer user token, POST JSON <=8KiB, an allowed browser origin, and no-store responses. SQL metadata RPC calls use the **user JWT**, not the privileged service key. Error responses omit upstream credentials/details.

- `cq-v4-student-account`: `{email}` -> `{invited:true}` after parent role/quota validation.
- `cq-v4-pdf-parent`: `{action,...args}`. Supports the existing list/create/upload/finalize/assign/unassign actions. `create_chapter` additionally requires `book_id`, `chapter_id`. Upload signing is create-only. Finalization reads and verifies `%PDF-` using privileged Storage, then invokes the service-only DB finalizer, which independently checks metadata/ownership.
- `cq-v4-pdf-link`: `{chapter_uuid}` -> `{signed_url,expires_at}`. Assignment is checked with the user JWT before privileged signing. URLs expire after 120 seconds.

A revoked relation blocks **new** RPC requests and PDF link issuance. Previously issued Storage URLs remain usable until their short expiry; already downloaded files cannot be revoked. Storage has no authenticated PDF policies and no audio UPDATE/DELETE policies. Audio INSERT is restricted to the assigned student before submission; SELECT is student/owning-parent scoped. As with any client/server split, final Storage upload vs submission concurrency needs dedicated live integration testing before enabling submission UI.

## Run and validate safely

Requirements: Node 24.22+ (native TS stripping), npm, Chromium. From the repository:

```sh
npm ci
npm run check
npm test
```

Browser tests use `/usr/bin/chromium`; override `CHROMIUM_PATH` if needed. They start a temporary loopback server, use disposable browser contexts and intercept **all external requests**. They do not use real accounts or send email. Database tests create a fresh in-memory PGlite PostgreSQL database, install all migrations, emulate Supabase Auth/Storage schemas and exercise real roles/RLS/PLpgSQL. They do not prove PostgREST/Auth/Storage/Deno service integration, parallel multi-connection race safety or email delivery. Edge tests exercise the actual shared TypeScript handlers with an injected HTTP/Storage adapter.

For manual frontend development with the installed environment's Wrangler:

```sh
cd /workspace/chapter-quest-v4-deploy
WRANGLER_SEND_METRICS=false XDG_CONFIG_HOME=/workspace/.chapter-quest-dev/config /workspace/.chapter-quest-dev/tools/node_modules/.bin/wrangler dev --local --ip 127.0.0.1 --port 8787
```

Use this repository path, not the old `/workspace/.chapter-quest-dev/app` snapshot copy. No deploy command is needed for these tests.

For a **new disposable hosted Supabase test project**, review/apply migrations in filename order, bootstrap a test parent, configure Auth redirect URL/SMTP, and configure Edge `APP_ORIGIN` to the exact test frontend origin. Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` inside its function runtime. Keep privileged values in secure settings only. `public/runtime-config.js` may contain only the test URL/public key, or use the existing parent settings UI. The existing browser URL validation currently supports hosted `*.supabase.co` projects; full local Auth/Storage UI routing remains unverified.

Do not link a CLI to production or run remote reset/push/deploy commands. The baseline intentionally fails on existing conflicting schema names; it does not merge/replace unknown existing tables, policies, functions or data.

## Acceptance status / next milestone

Locally tested: migration execution, roles/RLS, invitation expiration/single-use/approval/revocation, canonical IDs, idempotent approvals/publication, answer-key isolation, PDF readiness privilege boundary, audio policy checks, immutable submissions, feedback filtering, Edge authorization/signing, mocked account activation and selected-ID frontend wiring.

Unverified: real Auth email delivery/invite callback, live PostgREST serialization, Storage signed upload/download and concurrent behavior, Deno-hosted functions, existing production schema compatibility, actual student device PDF/microphone flow.

Next: run the complete chain in a disposable Supabase project. TXT wiring, local approval/PDF hash invalidation, audio backup import scope and student token refresh have been implemented in the continuation and locally tested; only after live authorization/submission recovery tests pass should the disabled submission UI be enabled. `/api/generate` is now implemented in the continuation; real model integration remains unverified. Production deployment, GitHub push/merge and environment publication are not part of this branch's work.
