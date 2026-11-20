# Stage 54 — recurring queue server contract (development only)

## Verified live schema, read-only (2026-11-20)
- Present: cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,timezone,created_at,released_at).
- Present: cq_v4_pdf_enrollments(parent_user_id,student_user_id,created_at), cq_v4_pdf_assignments(chapter_id,student_user_id,assigned_at), cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at,created_at), cq_v4_activities(chapter_uuid,questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id,approval_hash).
- Present: cq_v4_approval_requests(id,parent_user_id,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,content_hash,chapter_uuid,created_at).
- Present: cq_v4_student_submissions(chapter_uuid,child_user_id,answers,submitted_at,feedback,feedback_released).
- Absent: all four RPCs below and any separate recurring queue table.
- Existing cq_v4_publish_approved rejects changes to an already published approval and protects submitted work. Never bypass this.

## Exact browser RPC contract
1. cq_v4_parent_recurring_status() -> array rows with student_id, weekdays (PostgreSQL ISO 1=Mon..7=Sun), enabled, effective_from, book_title, current_title, next_title, chapter_title, chapter_number, state, pdf_ready, published, withdraw_chapter.
2. cq_v4_parent_enqueue_approved(p_approval uuid,p_students uuid[],p_chapter_number integer,p_book_title text,p_ends_book boolean) -> result checked by caller.
3. cq_v4_parent_enqueue_published(p_chapter uuid,p_students uuid[],p_chapter_number integer,p_book_title text,p_ends_book boolean) -> exactly p_chapter UUID.
4. cq_v4_parent_withdraw_recurring(p_student uuid,p_chapter uuid) -> boolean.

## Non-negotiable server invariants before deployment
- All writes verify auth.uid(), cq_is_admin(), PDF parent ownership, child enrollment, verified original PDF, immutable approved/published content, and unique student IDs.
- Queue keyed by parent + student + book + chapter_number; enforce unique ordering, atomic idempotent insertion, lock against concurrent enqueue and release, and forbid withdrawal after release or after a dependent next chapter.
- Parent-specific recurring config persists weekdays. Seowoo [1,3,4], Seojin [2,3,5]. Do not infer weekdays from lesson_schedule; schedule rows contain only individual dates.
- Release transaction uses Asia/Seoul current date, only the configured weekday, and no more than one new chapter per eligible student/day. It must check readiness, avoid duplicate assignments, and preserve prior releases.
- Do not rewrite existing cq_v4_lesson_schedule, cq_v4_student_submissions, cq_v4_activities, PDF originals, snapshots, or feedback. Existing Zack Ch1 remains unchanged.
- SECURITY DEFINER (if unavoidable) requires explicit auth checks, empty search_path, revoked PUBLIC/anon EXECUTE, authenticated-only GRANT; public tables require RLS/ownership policies. Prefer SECURITY INVOKER when RLS supports it.
- Frontend must not enable enqueue/withdraw solely because a stub status RPC returns rows. Full capability check or transactional backend deployment is required.
- Explicit parent approval and answer key must precede any new content publication. No automatic fabrication of legacy approvals.

## Required independent PostgreSQL tests (NOT YET RUN)
- anonymous/student RPC calls rejected; unrelated parent cannot view, enqueue or withdraw another parent's child.
- duplicate and concurrent enqueue idempotence; invalid chapter number and out-of-order chapter rejected.
- submitted/published chapter immutable; withdrawal after release denied; existing submissions/feedback unchanged.
- 23:59:59 / 00:00:00 Asia/Seoul boundary, DST-independent UTC conversion, weekdays Mon/Wed/Thu vs Tue/Wed/Fri, no weekend release.
- failure rollback of release transaction, repeated scheduler invocation, simultaneous releases, signed PDF entitlement after scheduled release.
- existing 3 schedule rows and student records unchanged by migration.

## Deployment gate
Do not apply any migration or redeploy Cloudflare before explicit separate approval.
Current parent UI deliberately fails closed when cq_v4_parent_recurring_status is absent.
A read-only placeholder RPC is NOT an acceptable production fix because it would falsely unlock queue writes.
