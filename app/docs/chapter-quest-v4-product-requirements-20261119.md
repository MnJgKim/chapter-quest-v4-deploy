# Chapter Quest V4 — confirmed product requirements and delivery sequence (2026-11-19)

Status: planning and development only. Do not deploy to production or mutate student data without explicit approval.

## Existing schedule and first-lesson safety
- Seowoo: Monday, Wednesday, Thursday; first lesson 2026-11-23.
- Seojin: Tuesday, Wednesday, Friday; first lesson 2026-11-24.
- Siwoo: configurable, potentially 3–5 days weekly.
- Preserve current manual schedules, published questions, original PDFs and submissions. Do not replace with untested auto-release.
- Student sees current week's dated assignments; a new lesson starts only on its scheduled day. Past lessons may remain accessible read-only for rereading and feedback, subject to existing access rules.

## Requirements and verification gates
1. **Student login efficiency:** when authenticated, hide login form and show concise account status. Existing `student-app.js` already conditionally renders login form only when no session. Verify on Galaxy tablet.
2. **Persistent child tablet session:** same student on own device should not reenter credentials for ordinary revisits. Existing dedicated child session recovery exists; verify refresh, token expiry, revoked sessions and shared-device isolation. Never store a password or disable server authorization.
3. **Weekly schedule:** three lessons/week per student's policy; weekly overview, only today's scheduled lesson starts, past lessons separately viewable. Check edge cases for missed lessons and time zone.
4. **Low accuracy:** after a *verified grading result*, show reread warning and explicitly say '학습 결과를 부모님께 알려드릴 예정입니다.' Implement real parent notification/record only after verifying consent, grading threshold, deduplication, and server-backed delivery. Do not claim parent notified unless delivered.
5. **Parent PIN and login persistence:** local PIN entry must be password-masked; existing `local-app.js` uses `input type=password`. Parent Supabase login should persist until logout, subject to session expiry/revocation. Verify device-specific auth and separate parent/child sessions.
6. **PDF reuse/storage:** retain approved original PDFs and permit a different authorized child to reuse the book at a later date, without duplicating binary objects if possible. Confirm access model and licensing. Before capacity is exhausted, estimate usage and ask parent to review archival/deletion of already-read books; never auto-delete and never change billing tier without explicit approval. Preserve submissions and snapshots even when a PDF is archived.
7. **FINAL DELIVERABLE, ONLY AFTER 1–6 VERIFIED:** a comprehensive ChatGPT Project instruction set with current architecture, approved workflow, book/PDF intake, text extraction, AI-generated questions with source checking, approval and publishing, student assignments, schedule, learning analytics, and safe operations. Use the Project for day-to-day learning management, not ordinary chat. Do not claim automatic Project-to-GitHub/Supabase access unless tools are actually connected.

## Implementation order
A. Low-risk UI wording (done in dev branch, not deployed).
B. Verify login visibility and masked PIN already implemented; fix only if tests show defects.
C. Verify persistent tablet sessions, role isolation and week/day gate.
D. Add accuracy-based reread warning + real parent notification with tests.
E. Design and test reusable PDF assignment and capacity alerts without deletions or upgrades.
F. After all above pass, write final Project instructions and operations handbook.

## Acceptance and rollout
- Every change must be tested, committed and distinguished from deployed functionality.
- Preserve operational data. No production SQL, Edge Function changes, Cloudflare deploy, PR merge or paid plan change without prior user approval.
- Before production deployment: backup, migration plan, rollback, smoke tests and explicit authorization.
