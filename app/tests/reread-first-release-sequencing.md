# Release sequencing — reread warning first, Chapter 2 deferred

Decision: keep the Magic Tree House #2 Chapter 2 correction independent of reread-warning rollout.

## Scope A (first): parent-only reread warning
- `app/public/js/parent-app.js` already renders `재독서 권장 · 부모 확인 필요` for objectively scored MC answers below 70% in parent submission details.
- It depends on `cq_v4_parent_lesson` supplying valid published questions and matching answer keys. If missing or mismatched, it silently shows no advisory; it is **not** a guaranteed server grade.
- The server reread progress/feedback gate in `app/sql/development-reread-progress-not-for-production.sql` is development-only. Production currently has no public `cq_v4_*reread*` functions (read-only catalog check).
- Warning-only frontend rollout and server-enforced feedback gating are distinct releases. Do not claim the gate exists merely because a warning appears.
- Verify that the warning is visible for 0/7–4/7 and absent for 5/7–7/7; malformed keys must show an explicit unscored status, never a false pass.
- Before any production Worker deployment: back up deployed assets and worker configuration, test the production build and parent login, provide rollback plan and request separate release authorization. No production SQL or deploy under this task.

## Scope B (defer until before planned 2026-12-09 use): Magic Tree House #2 Chapter 2
- Server already has the 10 questions; local parent book manager has only Chapter 1. The local editor cannot directly modify server Chapter 2. Do NOT create a duplicate chapter or generate new AI questions.
- Keep all 10 published questions (7 MC + 2 short + 1 inference), change only #7 MC answer to Red/index 1, preserve non-MC sample strings, old approval history, chapter UUID, PDF, assignments, submissions and snapshots.
- Implement a server-to-local **read-only draft import** or safe parent review workflow later, gated by exact UUID and explicit parent review.
- Do not use the six-question restore RPC or ordinary new-publication button on the existing published chapter.

These two scopes have no required code/data dependency. Separate PRs/releases are preferred.
