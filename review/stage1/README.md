# Chapter Quest V4 — first lesson release candidate

Status: NOT PRODUCTION READY. Production traffic has not been changed.
Target first lesson: 2026-11-23, Asia/Seoul.

This candidate preserves the existing `chapter_quest_v4_state` localStorage key and existing IndexedDB databases. It restores the manual parent approval removed in the preview package, adds faithful UTF-8 TXT originals alongside PDF originals, and validates server PDF selection before any approval registration request. It also adds an authenticated `/api/generate` Worker and replaces the old access-code-only frontend request with a parent Supabase session.

The AI endpoint is fail-closed until these settings have been verified and configured: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, AI_PARENT_USER_IDS (comma-separated exact authenticated parent user UUIDs), and the AI binding. Never place a service-role key in the client. Live inference has not been tested. Workers AI usage and any applicable costs must be reviewed before activating the integration.

Verified with isolated synthetic data: 28 browser checks; 16 API tests. The browser tests use Chromium, a virtual microphone and 360/412/800px viewports. PDF.js retrieves only the pinned public PDF.js scripts. All Supabase and actual AI requests are blocked/mocked. These tests do not establish live RLS correctness, cross-device persistence, real microphone behavior, or Galaxy device compatibility.

## Commands

```sh
node --test worker.test.mjs
python3 stage1_e2e.py public/index.html /tmp/cq-v4-isolated-qa
npx --yes wrangler@4.159.0 deploy --dry-run
```

`stage1_e2e.py` requires Playwright, Chromium and reportlab. Install them in an isolated environment; do not import real student records into the test.

## Release gates still open

- Read-only inspection of the actual Supabase project, installed functions, RLS and Storage policies.
- Authorized test parent/student accounts isolated from existing learning records.
- Invitation, approval, server PDF registration and assignment, real AI generation, audio upload, answer submission, feedback and cross-user denial tests.
- A separate decision on server TXT handling; current server publication still binds verified PDF chapters, while TXT works in local mode.
- Real Android/Galaxy tablet and microphone checks.
- Explicit user approval of production changes, costs/risks and rollback procedure.
- Production deploy and post-deployment verification.

## Rollback

The preceding production version is `7c3b8c1b-370e-4726-af3b-fe745f0eb064`. Candidate uploads do not route production traffic. Source and configuration backup: `/workspaces/cq-v4-stage1-20261110T104634Z/before.tar.gz`. Before production approval, inspect current deployment history again. Roll back Cloudflare traffic to the preceding verified version if post-deploy checks fail. This candidate contains no Supabase migration; never clear localStorage/IndexedDB as part of rollback.
