# Chapter Quest V4 student launch — verification and rollback gate

Target: Seowoo 2026-11-23, Seojin 2026-11-24 (Asia/Seoul). Student essentials gate: 2026-11-20 20:00 KST.

## Verified by read-only production inspection (2026-11-18)
- `cq-v4-pdf-link` Edge Function ACTIVE, version 2, JWT verification enabled.
- The function authenticates the student, checks assignment, enrollment, PDF readiness, and `cq_v4_is_released`, then signs a 120-second URL in `cq-v4-originals`.
- `student-api.js` calls `cq_v4_my_released_chapters` after the optional scheduler RPC; a missing scheduler may fall back only on its recognized 404 function-not-found response.
- Production RPCs `cq_v4_my_lesson_schedule`, `cq_v4_my_released_chapters`, `cq_v4_my_chapter_activities`, `cq_v4_my_submission`, `cq_v4_submit_answers` exist.
- `cq_v4_submit_answers` checks all answers, read completion, essay, speaking script, and an actual per-student audio object in `cq-v4-speaking`.
- Storage INSERT/SELECT policies for `cq-v4-speaking` are scoped by authenticated student, assignment, enrollment, and release.
- These checks are **not** a real student-session end-to-end test.

## Release blockers — do not mark complete without evidence
1. Record the latest GitHub Actions run ID, conclusion, and failing job logs; resolve only failing checks. The available GitHub connector may expose PR-triggered runs but not push-triggered runs.
2. With an authorized test/student session and without modifying production student data, confirm login, assigned chapter, Seoul weekly schedule, and original PDF download/page rendering.
3. Confirm vocabulary, questions, writing, voice recording, durable draft, and browser reload behavior on Android tablet. Use a separate authorized test student for write tests; do **not** submit or upload as Seowoo/Seojin during rehearsal without approval.
4. On an approved test identity, verify audio upload, server submission, immutable submitted view, feedback gating, and reload/history. Record evidence without tokens or personal answers.
5. Confirm the actual Seowoo 2026-11-23 Chapter 1 release and content are ready; do not change Chapter 1–10 schedule. Confirm Seojin's 2026-11-24 PDF separately after it is provided.
6. Verify release bundle and rollback before requesting production deployment approval.

## Production change gate
**Forbidden without explicit approval:** deploy, PR merge, production SQL migration, Edge Function/Worker/Stage Worker changes, assignment, student submission, or schedule edits.

Before asking for approval, provide:
- exact source commit and deployed commit/asset hashes;
- list of changed files and migration impact;
- backup locations for current Cloudflare static assets/Worker configuration and Supabase schema/settings;
- risks: browser cache, auth/session, PDF signing, microphone permissions, Storage RLS, scheduler fallback;
- tested rollback to the previous static bundle and Worker revision **without overwriting Supabase or student records**;
- post-deploy smoke checks and a stop/rollback threshold.

**No claim of production readiness is permitted until CI and real-device end-to-end checks have evidence.**
