# Existing PDF reuse — production approval required

The user selected the existing verified PDF titled `Chapter` for the first lesson. No hosted data, files, accounts or deployments have been changed for this work.

Candidate: `app/local-supabase/supabase/functions/cq-v4-pdf-parent/index.ts`. The added `download_url` action authenticates the caller, requires the existing authoritative `cq_is_admin()` boolean result, and selects only the chapter matching both chapter UUID and the caller parent UUID. It requires a verified PDF at the exact parent/chapter path, then issues a 120-second read-only signed URL. It performs no INSERT/UPDATE/DELETE/upload/assignment. Students, another owner, invalid paths and unverified originals are denied.

The frontend's `기존 PDF로 학습 준비` button downloads through the guarded PDF transport, stores exact bytes in the parent's local IndexedDB, extracts available text with the bundled PDF.js, and links the local chapter to the existing server UUID. It creates no duplicate hosted chapter and does not publish or assign any lesson. Image-only PDFs remain readable but require separately reviewed source text for AI preparation. Local browser data already present is retained.

Before an approved application, re-fetch the currently deployed Edge source/config and compare against the v2 backup in `current-baseline/`. Confirm the project ref, reviewed candidate commit, JWT verification enabled, and unchanged role guard. Do not deploy all local functions or apply the local bootstrap migration. Capture table fingerprints and storage metadata before/after.

Rollback: restore the immediately preceding captured `cq-v4-pdf-parent` source with its existing JWT verification setting, independently restore the captured Cloudflare frontend version if needed, and leave server rows/storage and local IndexedDB intact. `current-baseline/` captures the known deployed v2, including its admin guard; do not use the historical v1 backup that predates this guard. If the live baseline has changed since capture, preserve and restore that newer baseline instead.

Verified: 12 isolated Node checks cover ownership, denial, short signatures, URL trust and original byte validation; four additional mocked-browser checks cover fresh-parent reuse with exact bytes, extracted source and persistence after reload, repeat-import idempotency and preservation of an existing local TXT original. Real local Storage/Edge recovery is included in the full CI suite but remains pending until a successful run. These are development results, not production verification.
