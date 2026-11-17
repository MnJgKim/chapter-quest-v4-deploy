-- REVIEW ONLY. Do not apply to production without backup and explicit approval.
-- Distinguish manual releases from automatic future-day reservations.
-- Existing schedule rows remain manual/legacy and are never backfilled as automatic.
create table if not exists public.cq_v4_auto_release_arms (
 parent_user_id uuid not null,
 student_user_id uuid not null,
 chapter_id uuid not null,
 armed_at timestamptz not null default now(),
 revoked_at timestamptz,
 primary key(student_user_id,chapter_id),
 foreign key(parent_user_id,student_user_id)
  references public.cq_v4_pdf_enrollments(parent_user_id,student_user_id)
  on delete cascade,
 foreign key(chapter_id)
  references public.cq_v4_pdf_chapters(chapter_id)
  on delete cascade
);
-- No direct client write grants. Arm creation must occur in the same
-- transaction as the approved weekly scheduling RPC and must verify
-- the opt-in policy, cancellation tombstone, chapter approval and weekday.
-- Existing legacy released_at values MUST NOT be inferred as auto-armed.

-- Default public-schema grants vary; deny all direct client table access.
revoke all on table public.cq_v4_auto_release_arms from public,anon,authenticated;
alter table public.cq_v4_auto_release_arms enable row level security;
