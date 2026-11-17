-- READ ONLY. Opening readiness preflight for 2026-11-23.
-- Do not infer student names from UUIDs; verify identities in authenticated parent UI.
-- Run before any proposed migration, and compare row counts after any approved change.
select 'pdf_chapters' metric,count(*)::bigint value from public.cq_v4_pdf_chapters
union all select 'pdf_assignments',count(*)::bigint from public.cq_v4_pdf_assignments
union all select 'enrollments',count(*)::bigint from public.cq_v4_pdf_enrollments
union all select 'lesson_schedules',count(*)::bigint from public.cq_v4_lesson_schedule
union all select 'student_submissions',count(*)::bigint from public.cq_v4_student_submissions;

-- Hard stop if any student has more than one chapter on one lesson date.
select student_user_id,lesson_date,count(*)::bigint as scheduled_chapters
from public.cq_v4_lesson_schedule
group by student_user_id,lesson_date having count(*)>1;

-- Read-only readiness matrix; NULL indicates missing approved content/assignment.
select e.student_user_id,count(distinct a.chapter_id)::bigint as assigned_chapters,
 count(distinct s.chapter_id)::bigint as scheduled_chapters,
 count(distinct case when c.pdf_ready is true and c.pdf_verified_at is not null then c.chapter_id end)::bigint as verified_pdf_chapters
from public.cq_v4_pdf_enrollments e
left join public.cq_v4_pdf_assignments a on a.student_user_id=e.student_user_id
left join public.cq_v4_pdf_chapters c on c.chapter_id=a.chapter_id and c.parent_user_id=e.parent_user_id
left join public.cq_v4_lesson_schedule s on s.student_user_id=e.student_user_id and s.parent_user_id=e.parent_user_id
group by e.student_user_id order by e.student_user_id;

-- The planner RPCs and book tables must be present before the UI can schedule.
select 'books_table' requirement,to_regclass('public.cq_v4_books') is not null ready
union all select 'book_chapters_table',to_regclass('public.cq_v4_book_chapters') is not null
union all select 'auto_policies_table',to_regclass('public.cq_v4_auto_release_policies') is not null
union all select 'auto_arms_table',to_regclass('public.cq_v4_auto_release_arms') is not null
union all select 'auto_cancellations_table',to_regclass('public.cq_v4_auto_release_cancellations') is not null
union all select 'batch_schedule_rpc',to_regprocedure('public.cq_v4_parent_schedule_auto_week(uuid,jsonb)') is not null
union all select 'book_list_rpc',to_regprocedure('public.cq_v4_parent_list_books()') is not null
union all select 'book_mapping_rpc',to_regprocedure('public.cq_v4_parent_list_book_chapters()') is not null
union all select 'policy_list_rpc',to_regprocedure('public.cq_v4_parent_list_auto_release_policies()') is not null;
