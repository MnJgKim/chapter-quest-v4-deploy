# Chapter Quest V4 — integrated first-lesson candidate

Target: 2026-11-23, Asia/Seoul. Production has not been deployed or modified. Paid resources are not authorized.

## Structure

The repository root contains the only Wrangler configuration and npm lockfile. Runtime code is in `app/worker.mjs` and `app/public/`. Browser behavior is split into classic scripts under `public/js/`; their order preserves the existing state, localStorage keys, IndexedDB databases and backup format. The original ZIP and Git history remain intact.

The build copies the pinned PDF.js renderer/worker/license from the installed dependency into generated `public/vendor/` assets. No CDN is required in the student browser. Only `app/public/` is published as assets; server fixtures, local account credentials and review backups are outside it. Generated local credentials are ignored by Git.

## Learning flow

1. Parent unlocks the device screen and logs in. The server's `cq_is_admin()` result must be true. Switching accounts/logging out clears cached server submissions and PDF/student lists; late responses from an earlier identity are rejected.
2. Parent registers a local book/chapter and PDF or UTF-8 TXT. PDF text can be extracted for AI source review. TXT retains its original local file and can be rendered into a PDF for the existing private PDF backend without changing the hosted schema. Registering the current chapter links the verified server PDF; its title includes the book name to distinguish chapters across books.
3. Parent prepares questions/model answers manually, imports a validated JSON draft, or uses the authenticated AI route after Workers Free is verified. Review includes choices, answer keys, vocabulary and writing/speaking prompts. Parent approves, selects students and publishes activities with the verified PDF in one assignment path. The obsolete PDF-only assignment buttons are removed.
4. New browser profiles open student account mode. Existing local libraries retain demo mode; an explicit mode choice persists across reloads. Students can create a separate account (with password confirmation and email confirmation when required), then claim invitations and wait for parent approval, then choose their assigned chapters.
5. Student reads the original/converted PDF, reviews vocabulary with reveal/study controls and optional browser speech, answers comprehension/inference questions, writes in English and records speaking. Touch targets, jump navigation and a sticky final-submit bar are included. Malformed server question data produces an error rather than a blank form.
6. Answer and vocabulary drafts autosave by student UUID and chapter UUID on that device. Reload requires login again; re-login/chapter selection restores the correct draft. Audio is durably saved before submission. Recording stop is a local action, so token refresh cannot prevent stopping it. Upload failure preserves drafts; a lost submit response is checked against the server before retrying.
7. Final answers are immutable. The parent reads question text, selected choices, model answers, writing, vocabulary-review counts and submitted audio and explicitly releases feedback; the assigned student sees released feedback.

Malformed existing browser state is copied to a recovery key before display repair. Existing submitted records/custom metadata are retained. If the recovery copy cannot be stored, normal saving is blocked instead of overwriting the original. A failed runtime asset shows a recovery screen rather than an empty page.

## Verified locally

- 87 Node checks: authenticated AI handling/free-plan lock, origin restrictions, state repair, asset existence, sanitized student question transport, parent PDF ownership/signature denial and original byte integrity, and parent recording access scoped to finalized authorized submissions.
- 24 isolated PostgreSQL checks using captured hosted function definitions.
- 34 local-browser checks including PDF/TXT originals, PDF text extraction, question selection, audio, final submission, feedback, preservation, malformed state and failed-asset recovery.
- 52 mocked-server browser checks: parent/child invitation, TXT-to-PDF signed upload, PDF binding/publication, vocabulary, touch input, 360/412/800/1280px active-learning layouts, refresh/login draft recovery, same-browser student separation, audio retry/lost-response recovery, parent cache clearing, authorization rejection, and fresh-browser recovery of an existing PDF with exact bytes/extracted source retained after reload, repeated recovery without duplicate chapters and preservation of the local TXT original, and clearing stale server associations when the original is replaced, parent PDF/TXT preview and actual recording playback. Both parent results/playback and student recording/submit screens are checked at all four viewport sizes.
- 30 real lean-local Auth/PostgreSQL/PostgREST API checks and 9 independent real-local browser checks. In the lean setup, storage objects are SQL fixtures; it does not run Storage API/Edge services.
- Five previously executed live anonymous denial checks. Hosted authenticated writes have not been used for testing.
- 19 full real-local Supabase browser/API checks passed on free GitHub Actions: actual Auth, PostgreSQL, private Storage, both Edge functions, PDF/TXT upload and rendering, recording upload/playback, submission, feedback, fresh-parent PDF recovery and another registered parent denial. Evidence: `qa-results/full-local-supabase.json`. No hosted service or AI request was used.
- Root deployment dry-run succeeds. Actual deployment has not run.

Machine-readable results are in `qa-results/`. The new GitHub Actions workflow uses only a standard Linux runner on this public repository, has read-only repository permission, no production secrets and no deploy step. It runs a complete ephemeral local Supabase stack and `local-supabase/full_browser_test.py`; run [42968594077](https://github.com/MnJgKim/chapter-quest-v4-deploy/actions/runs/42968594077) passed all steps on runtime commit `a4b8874`, including two real assigned students on the same chapter. The final expansion also repeats assignment after parent logout/re-login; its result is in the latest PR checks.

## Free operation and remaining gates

`AI_FREE_PLAN_CONFIRMED=false` keeps inference disabled until the correct Cloudflare account is verified as Workers Free. The manual/JSON lesson path makes no AI API call. Do not upgrade plans or enable paid inference. See `FREE_LESSON_PREPARATION.md` and `TEST_ENVIRONMENT_PLAN.md`.

Before production readiness: verify the intended Galaxy device and microphone; review the selected existing `Chapter` PDF and its questions/student assignment; confirm the correct free Cloudflare account; inspect the immediately preceding deployment and obtain explicit user deployment approval. Viewport/touch emulation is not a physical Galaxy test. No synthetic fixtures may be written to production.

## Rollback

Capture the live Cloudflare deployment version/settings immediately before an approved release. If post-release checks fail, restore traffic to that captured version and verify the original page/login. Keep the same browser profile and retain JSON backups plus original PDF/TXT/audio files separately; JSON backup does not include those binary files. Do not clear IndexedDB/localStorage or delete server rows/objects during rollback.

This candidate additionally proposes one additive parent-only read function, `cq_v4_parent_lesson(uuid)`, for canonical question/model-answer context in parent results. It does not replace existing functions or change existing rows/tables/policies. It is applied locally only and requires explicit production approval; see `server-review/PARENT_CONTEXT_APPROVAL.md`. A separate parent Edge addition is proposed for read-only recovery of existing originals and authorized submitted recording playback; see `server-review/PDF_REUSE_APPROVAL.md`. Its current deployed v2 source is preserved separately from the historical v1 backup. Local Edge fixtures pin the SDK and use relative signed URLs so the local gateway is reachable from the browser; production's absolute signed URL response remains supported. The historical server repair/rollback files are retained as evidence and must not be applied as part of this release.

Verified Git-history backups exist at `/workspace/chapter-quest-v4-before-changes.bundle` and `/workspace/chapter-quest-v4-before-integration.bundle`. They are source backups, not database backups.

The latest first-lesson priority audit is `FIRST_LESSON_AUDIT.md`. Damaged student draft/upload-intent containers are backed up verbatim before repair; backup failure blocks overwrite and is visible in the form. AI source is saved before generation, and successful-save status/cloud sync are withheld when device storage fails. A post-submit feedback action completes the student flow. Parent and student account references can be compared before choosing an existing student. No hosted schema or Edge source changed in this follow-up.

Publication request keys now remain stable across parent login sessions. Exact matching legacy keys are retained and reused; conflicting or damaged keys stop publication instead of silently generating a duplicate approval.

Parent page selection is documented in `PDF_PAGE_SELECTION.md`. It starts with empty bounds, supports page-by-page preview and direct start/end picking, invalidates changed previews, and preserves the original/TXT while preparing only a confirmed derived PDF. Existing unconfirmed server originals cannot generate/publish a lesson. Local page-selection browser checks passed (20); the full local range flow passed 35 checks on commit `6216a96` (run 42977144848), alongside TXT/PDF 31 checks each. A final explicit original-PDF access-denial assertion is in the latest PR checks. Anonymous account continuation is reviewed, not implemented or applied: `ANONYMOUS_ACCOUNT_REVIEW.md`. The actual Chapter 1 range remains undetermined.

Latest safe integration verification (2026-11-13): [P0 reconciliation and first-lesson gate](P0_INTEGRATION_20261113.md). The latest GitHub application stays active; all 50 historical Codex P0 files and its Git history are preserved under `archive/`. Current local counts: 209 Node, 44 current-schema/preservation, 25 extra server-review, 163 browser, 39 real lean-local Auth/REST/browser and 5 independent database recovery checks. JSON restore now validates and preserves pre-restore data; it does not claim to back up binary originals. Operating release and physical Galaxy gates remain unverified.
