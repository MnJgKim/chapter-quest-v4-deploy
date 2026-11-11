# Chapter Quest V4 — 2026-11-23 first lesson candidate

Implementation and isolated verification are complete for the flows listed below. **Hosted authenticated integration, real AI inference and production deployment are not complete.** Production traffic and existing Supabase data have not been changed.

This continues `review/v4-launch-20261110` (commit `7a2af0e`), preserving its existing fixes and tests. The live HTML at `https://chapter-quest-v4.roscabear.workers.dev/` matches the original ZIP exactly (SHA-256 `e8339dbf01495ea78d0d79ad09014c9245e85b15069fba23d58d7db58ad9dfd6`). That ZIP's Wrangler configuration serves static assets without the `/api/generate` handler used by the UI.

## Changes

- Retain the previous candidate's parent login, explicit verified-PDF binding, manual approval and faithful local TXT reader.
- Route `/api/generate` through a Worker with Supabase identity verification and authoritative `cq_is_admin()` authorization. An optional parent allowlist can further restrict access; editable user metadata never grants access.
- Reject malformed AI output, invalid multiple-choice answer indices and missing written model answers. Show choices, answer keys, vocabulary and activity prompts to the parent before approval. Discard AI responses when the account, chapter or source changes.
- Enable final student submission only after the assigned original PDF has downloaded and rendered. A failed PDF request keeps submission locked. The server independently checks enrollment, assignment, publication, complete answers and the uploaded recording.
- Refresh student access tokens in memory, preserve answer drafts, preview saved recordings, retry failed uploads and recover lost submission responses without inserting a second submission.
- Preserve existing localStorage keys and IndexedDB databases. JSON backup still excludes original files and recordings; those must be retained separately.

## Current evidence

- 28 local-browser checks: original PDF/TXT reading, questions, drafts, recording, submission lock, parent feedback, record preservation and mobile/tablet viewport widths.
- 16 separate parent/student browser integration checks with synthetic HTTP responses, an actual PDF renderer and a virtual microphone. Includes invitation/approval, signed upload/finalize, approval/binding/publication, token refresh, audio playback, failed upload, lost submit response recovery and feedback release.
- 21 isolated PostgreSQL checks using the current hosted V4 function definitions: authorization, answer secrecy, publication contract, incomplete/invalid answer rejection, immutable duplicates and feedback release.
- 20 AI Worker tests using mocked identity, role and inference responses.
- 5 read-only live anonymous HTTP checks: all RPC/Edge endpoints deny missing user authentication.
- Read-only counts and row-set fingerprints of 17 CQ tables match across this session. No production account or learning row was changed.
- Wrangler 4.159.0 deployment dry-run succeeds. No deployment upload or traffic change was performed.

Detailed machine-readable results are in `qa-results/`; browser scripts state their mock boundaries. Isolated checks do not establish hosted Auth/Storage correctness, actual model quality, cross-device persistence or real Android microphone behavior.

## Remaining release gates

1. Connect the correct Cloudflare account in a secure environment. No Cloudflare identity or token is configured in this session. Do not paste tokens or account passwords into chat or commit them.
2. Use a fresh development branch with no production data and new test-only parent/student accounts for hosted account/PDF/audio/feedback tests. See [TEST_ENVIRONMENT_PLAN.md](TEST_ENVIRONMENT_PLAN.md). Do not create accounts or fixtures in production.
3. Verify actual Workers AI generation and review a real lesson's questions and model answers. The Worker uses `@cf/meta/llama-3.3-70b-instruct-fp8-fast`; confirm account availability and usage costs before enabling production traffic.
4. Verify the first lesson's real source PDF, approved activities, target student enrollment and assignment, plus microphone behavior on the intended device.
5. Record the current Cloudflare deployment version and show the final change/rollback review to the user. Obtain explicit production approval before deployment or traffic changes.

No Supabase migration is proposed in this candidate: the current inspection confirms that the parent Edge role gate, strict submission validation and reduced table administrative privileges from the prior repair plan are already installed. `server-review/APPROVAL_PLAN.md` is retained as historical context, not a pending operation.

## Developer verification

Use the committed lockfiles. From this directory, `npm ci`, `npm test` and `npm run build` verify the Worker and dry-run package. Python browser tests require the packages in `qa-requirements.txt` and Chromium. `server-review/current-db.test.mjs` uses its own committed PGlite dependency. The agent runs these commands; the user does not need a terminal.

## Rollback

Before any approved release, capture the immediately preceding live Cloudflare version and settings. If post-release checks fail, route traffic back to that captured version, verify the original page and login, and stop further publishing. The old deployed HTML has a known broken AI path, so rollback restores the preceding behavior rather than resolving AI generation.

Do not clear localStorage/IndexedDB, delete records or remove uploaded PDFs/recordings during rollback. Keep the same browser profile and preserve a browser JSON backup and original files before release. Existing submissions remain immutable. Because this candidate changes no hosted SQL or Edge Functions, a Cloudflare rollback requires no database rollback.

Original complete Git-history backup: `/workspace/chapter-quest-v4-before-changes.bundle` (verified); the original ZIP remains tracked unchanged. Historical deployment version IDs from earlier work must be rechecked and must not be assumed to be current.
