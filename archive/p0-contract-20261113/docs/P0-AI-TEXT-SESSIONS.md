# P0 continuation: AI, TXT, approval and sessions

This extends commit `1488598` on the same work branch. The original SQL/RPC,
invitation/account issuance and canonical PDF/chapter assignment contract are reused.
No remote database, Cloudflare deployment, environment publication or GitHub main
update is part of this work.

## AI API

`worker/index.js` implements `POST /api/generate` and delegates non-API requests to
the existing static assets. `wrangler.jsonc` now declares the Worker entrypoint,
ASSETS binding and AIQuota Durable Object; these are source configuration changes,
not an applied deployment.

The request/response shape remains compatible with the existing app:

- Request: `{title, chapter, source}`; source is 250–45,000 characters, request body
  at most 200,000 bytes, title/chapter at most 200 characters.
- Auth: parent's Supabase Bearer token, independently checked with Auth `/user`
  and existing `cq_v4_my_role`. `X-CQ-Access` is tolerated for old callers but
  **cannot authorize a request**. Users must sign in to the parent cloud panel.
- Model: fixed OpenAI HTTPS endpoint, configurable model (default `gpt-4.1-mini`),
  JSON output, 8,000 completion-token ceiling and a 45-second request budget.
  Source is explicitly treated as untrusted chapter data, separate from instructions.
- Output: validated questions, vocabulary, writingPrompt and speakingPrompt.
  Unsupported kinds, invalid correct indices, missing model answers, malformed or
  truncated output are rejected. Keys and raw provider errors never enter responses.
- Quota: ten attempts per verified parent/project in a rolling hour, persisted
  transactionally in a Durable Object; missing configuration fails closed (503).
- Drafts are never approved or published by the API. A human parent reviews them.

Only TEST credentials are needed for actual external integration. `.env.example`
contains **names only** for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENAI_API_KEY`
and the nonsecret model setting. Use ignored `.dev.vars` or secure test deployment
settings; never commit credential values. AIQuota/ASSETS are local bindings. No
service-role credential is needed by the Worker. In this cloud environment,
actual outbound provider/test-project requests also need their domains allowed;
this task did not alter the environment policy or send actual model requests.

## TXT and compatibility

The existing book/chapter editor now connects `textFile` to UTF-8 TXT/PDF text
extraction. A book can also create a new chapter directly from a TXT file.
Limits: 5MiB input and 1–45,000 text characters. PDF extraction does not perform OCR.
The original data fields, IDs, question format and PDF workflow are retained.

A TXT chapter (`readingType='txt'`) can be read locally without a PDF. The student
projection includes original TXT content only for TXT chapters; PDF analysis text
is still omitted from the PDF reading view. All text is rendered as escaped text.
Registering a PDF switches that local chapter back to PDF reading and revokes its
approval. Old chapters default to PDF mode.

`202611160001_text_chapters.sql` is an **additive test-project migration**:

- Adds `material_type`/`reading_text` to the existing chapter table.
- `cq_v4_register_text_chapter` maps the existing parent/book/chapter IDs to the same
  canonical UUID. Published text is immutable; revisions require a new chapter ID.
- The legacy `pdf_ready` field acts as material readiness for TXT compatibility;
  it is not evidence of a binary PDF on a TXT chapter.
- Existing approval/publication/assignment RPCs remain in use. A trigger rejects
  TXT publication if the approved source differs from its actual reading text.
- `cq_v4_my_reading` exposes original TXT only to an actively linked assigned
  student with published material. It does not expose answer keys.
- The parent publish button registers the TXT original before invoking the existing
  approval/publication sequence. The student view fetches its reading format and
  uses the existing PDF transport only for PDF chapters.

Install this new migration **after** the three P0 baseline migrations in a disposable
test project. Clients now require the new reading RPC. This is not a reviewed
upgrade of an unknown production schema; no migrations were applied remotely.

## Approval rules

Local students see/open/submit only chapters with a verified version-2 approval.
The receipt covers TXT/original text, question content, vocabulary, prompts,
reading type and the binary PDF SHA-256 where applicable. PDF bytes are checked
again at open and submit. Changing source, questions, prompts or PDF invalidates
publication. Automatic/manual schedule choices filter out unapproved material.

Version-1 receipts are intentionally not upgraded to verified status: parents must
review and approve those chapters again. Existing content/records remain intact.
This is a local workflow gate, **not** a defense against a person controlling the
same browser/localStorage; Supabase roles/RLS/RPCs are the server boundary.

## Audio restoration and session isolation

The existing manifest/file import listener is moved from the parent closure into
the student closure. It reuses existing UUID, MIME, size and SHA-256 verification,
submission gate, Web Locks and IndexedDB vault. A failed/mismatched import cannot
overwrite valid stored audio. The async download handler is awaited. Storage-relative
URLs are normalized before the existing same-origin audio check.

`public/student-session.js` provides memory-only rotating access/refresh tokens:

- Refresh 60 seconds before expiry, deduplicated across concurrent requests.
- Verify refreshed user identity, fail closed and clear the UI on refresh failure.
- Epoch checks reject late login, refresh and streamed data from old sessions.
- Abort pending network operations on reset, without pre-buffering large PDFs.
- Logout, parent/student or storage-mode switching and project changes clear auth,
  chapter lists, player URLs, microphone streams, pending memory-only voice imports,
  cached parent results and AI drafts. Pending AI requests are cancelled/discarded.
- Account/chapter-scoped saved drafts and durable recordings are preserved for
  recovery; account switching does not erase learning data. Unsaved voice navigation
  still requests confirmation through the existing guard.

## Verification and remaining limits

Run from repository: `npm run check` and `npm test`. Automated tests use isolated
PGlite PostgreSQL, disposable Chromium with intercepted external requests, fake
provider/HTTP adapters and in-memory quota storage. They test actual migration
SQL, real browser crypto/IndexedDB, approval revocation, TXT reading and refreshed
request headers. Provider quality, hosted Deno/Auth/Storage/PostgREST integration,
real microphone hardware and distributed Durable Object behavior remain unverified.

The actual local Wrangler/workerd runtime was also started: static assets returned
200, unsupported API methods 405, unauthenticated generation 401, unknown APIs 404,
and a credential-free configured-route probe failed closed with 503. No provider
or hosted Supabase credentials were used for that smoke check.

Final student server submission remains intentionally disabled pending the full
isolated Supabase/device recovery rehearsal; this continuation does not claim the
entire learning workflow is ready for the first lesson. Next: validate actual model
outputs with test credentials, run the real invitation→material→assignment→student
learning→recording→submission→feedback chain in a disposable project, then review
submission activation and recovery behavior.
