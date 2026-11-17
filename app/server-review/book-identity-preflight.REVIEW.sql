-- READ ONLY: execute before approving book identity migration.
-- These checks must not change existing PDFs, assignments, submissions or schedules.
select 'chapter_total' as metric,count(*)::bigint as value from public.cq_v4_pdf_chapters
union all
select 'assignment_total',count(*)::bigint from public.cq_v4_pdf_assignments
union all
select 'schedule_total',count(*)::bigint from public.cq_v4_lesson_schedule;
-- Group candidate chapter labels by owner. This is NOT book identification.
select parent_user_id, title, count(*)::bigint as occurrences
from public.cq_v4_pdf_chapters
group by parent_user_id,title
order by parent_user_id,title;
-- Titles like 'Chapter 1' are ambiguous across books. Manual book assignment
-- or a trusted source with explicit book identity is required.
-- After migration, verify zero cross-owner mapping rows:
-- select count(*) from public.cq_v4_book_chapters bc
-- join public.cq_v4_pdf_chapters c on c.chapter_id=bc.chapter_id
-- join public.cq_v4_books b on b.book_id=bc.book_id
-- where c.parent_user_id<>bc.parent_user_id or b.parent_user_id<>bc.parent_user_id;
