# P0 integration and first-lesson gate — 2026-11-13

Target: 2026-11-23, Asia/Seoul. This is implementation and local verification,
not approval to alter `english-v3b-test` or deploy Cloudflare.

## Preservation and reconciliation

- Workspace started clean (no unstaged, staged or untracked user changes).
- Before edits, complete Git bundle verified and cloned to an independent restore
  checkout; source archive entries matched the checkout bytes. Private backups
  are outside the Git checkout, under `/workspace/.chapter-quest-dev/safety-20261113`.
- Local P0 head: `5f38010`. GitHub target head at integration: `d58761b`.
- GitHub's target contains substantially newer PDF-range, review, identity,
  draft/submission and feedback work. It is the active application baseline.
- Every one of the local P0's 50 tracked files is preserved byte-for-byte under
  `archive/p0-contract-20261113/`; its commits are a merge parent, not discarded.
- A pre-existing local `work` branch prevented the required `work/...` ref name.
  It was renamed to `preserved-work-20261113`, retaining the same commit; its
  original name also remains recoverable from the verified bundle.

| Local P0 capability | Active compatible implementation / decision |
| --- | --- |
| Parent authorization | Existing `cq_is_admin`, parent-app and captured-schema security tests retained. The fresh-project profile baseline is archival only. |
| Account issuance/invite/approval | Existing student signup/confirmation and parent-code claim/approval retained; 30 real Auth/REST and 9 real browser checks. No existing account was recreated or converted. |
| PDF/TXT identity | Existing verified PDF binding and reviewed range manifests retained. TXT is preserved and converted to private PDF for the installed schema. No duplicate active schema. |
| AI drafts | Existing parent-authenticated Workers AI candidate retained with `AI_FREE_PLAN_CONFIRMED=false`. Manual/reviewed JSON path tested without inference. Archived paid adapter is never built or called. |
| Approval-only visibility | Existing parent review/hash/range checks, canonical binding/publication and sanitized student transport retained and tested. |
| Audio restore / sessions | Newer vault/lifecycle, recovery intent, refresh, same-project and late-response guards retained. |
| Guarded integration tooling | Preserved in full in the archive; fresh-project tooling is not suitable for the existing hosted project. |

## Fixes made during this run

1. Build failed attempting to write Wrangler settings in a read-only home.
   `tools/run-wrangler.mjs` uses a writable ignored settings path, forces local dev,
   and permits only dry-run builds. It rejects a live deployment command.
2. Python browser suites assumed downloaded Chromium. `qa_browser.py` uses pinned
   Playwright with its bundled browser or an explicitly installed system Chromium.
   Existing test logic is preserved; no user profile is opened.
3. Real lean-browser test used an obsolete post-submit `view` selector. It now
   exercises the implemented `feedback` action; the real test passes.
4. Malformed JSON backup could normalize an invalid `books` object into an empty
   library. Restore now validates the backup, verifies a verbatim pre-restore
   recovery copy, verifies the write, and preserves the original on failure.
   Device restore pauses cloud autosync and refuses overlap with an in-flight save.
5. Backup wording now explicitly says records JSON; PDF/TXT/audio are separate.
   Browser tests confirm JSON restore preserves existing IndexedDB bytes and a
   fresh profile cannot pretend its missing PDF was recovered from JSON alone.
6. Unsupported model question kinds are rejected, preserving supported historical
   labels rather than silently converting arbitrary provider output into a lesson.

## Actual results from this execution

- `npm ci --ignore-scripts --no-audit --no-fund`: successful, frozen root lockfile.
- Pinned Python QA requirements installed in ignored local venv: Playwright 1.65.0,
  ReportLab 5.1.0, Pillow 13.0.0, greenlet 3.5.6, charset-normalizer 3.5.2.
- `npm test`: 209 active Node tests, 0 failed/skipped. Captured-schema isolated
  PostgreSQL checks: 40 passed; additive migration preservation: 4 passed.
- Additional isolated server-review suite: 10 Edge checks and 15 candidate DB checks passed.
- Historical P0 regression suite: 49 passed, 0 failed/skipped, in the archive.
- `npm run build`: successful dry-run, no deployment. Vendored PDF renderer built.
- `npm run test:browser` with pinned Python: 34 local lesson, 67 mocked server,
  20 page-range, 13 parent review, 17 existing-session and 12 backup/touch checks.
  These 163 checks have no application page errors or unmocked hosted requests.
- Real isolated GoTrue 2.197.0 / PostgreSQL 17 / PostgREST 16.5: 30 API checks and
  9 independent browser checks passed. Synthetic local identities only.
  Storage objects in this lean environment are SQL fixtures; these results do
  **not** prove actual Storage API or Edge runtime service behavior.
- Local database custom-format dump restored into a new independent database:
  5 checks passed for all public/Auth/Storage rows, ACL/RLS, function definitions
  and unchanged source. No DROP/TRUNCATE/DELETE or existing database overwrite.
- Python compile checks passed. Four touch viewports: 360x800, 412x915, 800x1280,
  1280x800; active learning, recording, feedback and parent results also tested.
  Fake microphone success does not establish hardware/Android codec behavior.

Private synthetic reports/backups stay outside Git. Sanitized counts and scope
are recorded in `qa-results/safe-integration-20261113.json`.

## 23 November readiness — development candidate, not live-ready

Independent coding and local verification are complete for this change. The
following gates are still unverified/forbidden under the current instruction:

- No deployment was performed. Existing operating frontend cannot gain these
  features merely because the GitHub branch has changed.
- No SQL/RPC/Edge changes were applied to the hosted project. See the pre-existing
  `OPERATING_CHANGE_INVENTORY.md` and server-review approval/rollback files for the
  exact candidate objects. Archived bootstrap is excluded.
- No operating Auth login/token refresh/account creation, source download,
  publication, assignment, submission, feedback or data/file deletion was done.
- Actual Seowoo anonymous identity/session must be verified on the original
  device/profile. Do not substitute a new account or erase browser storage.
- Repository handoff records identify the intended existing 11-page Chapter PDF,
  but this execution did not inspect the real file or validate its lesson content.
  Synthetic test questions must not be used for that actual first lesson.
- Real Galaxy microphone, codecs, sleep/IME/rotation and large original PDF
  behavior remain physical-device acceptance checks.
- Actual AI inference and Cloudflare plan/rollback access are unverified. No model
  call, upgrade, paid resource or deployment was requested. The free manual/JSON
  route is the available no-cost preparation path.

Before any authorized live release, capture the actual prior deployment/version
and recovery access plus hosted schema/Auth/Storage backup coverage. Local and
Git backups are not an existing hosted database backup. Operation and data-write
approvals must identify the exact release/objects and preserve existing records.
The integration commit uses `[skip ci]` to avoid scheduling remote jobs or
unintended additional costs; the validation reported here was executed locally.
