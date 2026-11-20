# Chapter Quest V4 — read-only live integration and Galaxy tablet matrix

Status: PREPARATION ONLY. No production credentials, SQL changes, data writes, deployments, student assignments or device testing performed by this document.

## Environment guardrails

1. Record immutable branch SHA and successful GitHub Actions URL. Verify target Supabase project and Worker URLs match the intended existing deployment. Never paste service-role keys into a browser, issue test writes to production, or deploy REVIEW-ONLY SQL without explicit approval.
2. Confirm only public/anon keys are in browser configuration; never expose answer_key, approval_hash, JWT, refresh token, signed storage URL or full student answers in screenshots/logs.
3. Use existing authorized accounts only. Do not create students, approve assignments, submit answers, acknowledge notifications, or upload recordings merely to test production.
4. Capture redacted HTTP status, endpoint category, expected/observed behavior and timestamp. Do not collect tokens, personal answers, file bytes or account identifiers.

## Non-mutating inspection checklist (not executed)

| Area | Safe observation | Pass condition | Requires existing data / caveat |
|---|---|---|---|
| Parent login | Existing parent signs in and signs out; do not change account settings | Correct parent role and no stale inbox after logout | Login may rotate auth refresh token; not strictly network-read-only |
| Student login / refresh | Existing student signs in, waits for near-expiry or tests a previously authorized session | Token refresh preserves same UID; changing student discards old view | Authentication state changes; coordinate real-device session tests |
| Released chapter | View existing assigned chapter list, do not call scheduling mutation for test | Only already-authorized released chapters visible | Current student API calls ensure_today RPC; this can assign a chapter. **Do not invoke in production without approval** |
| Original PDF | Reopen previously submitted authorized PDF only | Signed URL path and token validated; no new assignment | Signed URL generation creates short-lived access token; no stored object write |
| Student submission | Read an existing submitted record only | Immutable submission and released feedback unchanged | Do not press final submit or edit answers |
| Reread suggestion | View an already-submitted chapter with parent feedback released | Boolean advice only, no score/key, graceful RPC absence | New RPC is REVIEW-ONLY and may be absent in hosted project |
| Parent notice inbox | View only if RPC already installed; never press acknowledge in production | Parent-only records, no answer key | Acknowledge is a **write**; requires explicit approval |
| Audio | View existing recording metadata or authorized playback | Same-student access, no new recording upload | Upload and delete are writes; skip without approval |
| Tablet | Test Chrome on Galaxy tablet using already-authorized session | No blank screen, landscape/portrait usable, logout clears parent inbox | Cannot certify until physically executed |
| Seoul midnight | Inspect existing schedule rules and UTC/Asia-Seoul conversion without invoking scheduler | Local 23:59 to 00:00 switches date once | Use isolated PostgreSQL time fixtures; do not force production clock |

## Release blockers

- CI checks must be green at exact deploy SHA; record any later commits and rerun affected checks.
- REVIEW-ONLY parent notice / student suggestion SQL is not a production deployment; live RPC presence and schema compatibility must be verified before enabling.
- No live Supabase authenticated PDF, recording, refresh-token, feedback, or Galaxy tablet end-to-end verification is yet evidenced.
- Confirm rollback to a known-good Git SHA and take an authorized database backup before any approved migration or deployment.

## Reporting template

For each row record: test date/time (Asia/Seoul), SHA, environment (isolated / existing live read-only / tablet), observed result (PASS / FAIL / NOT RUN), redacted evidence, user approval if a write was necessary. Never label NOT RUN as PASS.
