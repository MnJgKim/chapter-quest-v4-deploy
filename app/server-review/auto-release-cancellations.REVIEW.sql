-- REVIEW ONLY: cancellation tombstones survive later planner runs.
-- Cancellation is per student/chapter, not per date, so moving a lesson
-- cannot silently undo a parent's explicit cancellation.
create table if not exists public.cq_v4_auto_release_cancellations (
 parent_user_id uuid not null,
 student_user_id uuid not null,
 chapter_id uuid not null,
 cancelled_at timestamptz not null default now(),
 primary key (student_user_id,chapter_id),
 foreign key (parent_user_id,student_user_id)
  references public.cq_v4_pdf_enrollments(parent_user_id,student_user_id)
  on delete cascade,
 foreign key (chapter_id) references public.cq_v4_pdf_chapters(chapter_id)
  on delete cascade
);
-- No client grants are included. A separate authenticated SECURITY DEFINER
-- RPC must verify parent ownership and update policy/cancellations.
-- Never grant direct INSERT/UPDATE/DELETE on these tables to authenticated.

-- Default public-schema grants vary; deny all direct client table access.
revoke all on table public.cq_v4_auto_release_cancellations from public,anon,authenticated;
alter table public.cq_v4_auto_release_cancellations enable row level security;
