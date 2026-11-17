-- REVIEW ONLY: book identity for reliable multi-book scheduling.
-- NOT deployed. Requires complete production backup and explicit approval.
-- Existing cq_v4_pdf_chapters and schedules remain untouched.
create table if not exists public.cq_v4_books (
 book_id uuid primary key default gen_random_uuid(),
 parent_user_id uuid not null references auth.users(id),
 title text not null check (length(btrim(title)) between 1 and 300),
 created_at timestamptz not null default now(),
 unique(book_id,parent_user_id)
);
-- Parent consistency is enforced at the database level, not just in the UI.
create unique index if not exists cq_v4_pdf_chapters_owner_key
 on public.cq_v4_pdf_chapters(chapter_id,parent_user_id);
create table if not exists public.cq_v4_book_chapters (
 chapter_id uuid primary key,
 book_id uuid not null,
 parent_user_id uuid not null,
 chapter_number integer not null check(chapter_number between 1 and 10000),
 foreign key(book_id,parent_user_id) references public.cq_v4_books(book_id,parent_user_id),
 foreign key(chapter_id,parent_user_id) references public.cq_v4_pdf_chapters(chapter_id,parent_user_id) on delete cascade,
 unique(book_id,chapter_number)
);
-- Parent-scoped access only; do not grant direct access until policies,
-- enrollment checks, and SECURITY INVOKER / audited RPCs are ready.
alter table public.cq_v4_books enable row level security;
alter table public.cq_v4_book_chapters enable row level security;
revoke all on public.cq_v4_books from public,anon,authenticated;
revoke all on public.cq_v4_book_chapters from public,anon,authenticated;
-- Migration requires preflight: check owner matches chapter parent_user_id,
-- ensure every chapter maps to at most one book, and manually classify
-- existing 'Chapter N' titles. Never infer book_id from a title alone.
