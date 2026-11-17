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

-- Launch blockers, read-only: a zero value for every metric is required.
select 'chapter_pdf_unverified' metric,count(*)::bigint value
 from public.cq_v4_pdf_chapters where not pdf_ready or pdf_verified_at is null
union all select 'unpublished_activities',count(*)::bigint
 from public.cq_v4_activities where published_at is null
union all select 'schedule_without_assignment',count(*)::bigint
 from public.cq_v4_lesson_schedule s where not exists
 (select 1 from public.cq_v4_pdf_assignments a
  where a.student_user_id=s.student_user_id and a.chapter_id=s.chapter_id)
union all select 'schedule_without_published_activity',count(*)::bigint
 from public.cq_v4_lesson_schedule s where not exists
 (select 1 from public.cq_v4_activities a
  where a.chapter_uuid=s.chapter_id and a.published_at is not null)
union all select 'duplicate_student_dates',count(*)::bigint
 from (select student_user_id,lesson_date from public.cq_v4_lesson_schedule
       group by 1,2 having count(*)>1) x;

-- Strict auto-scheduler approval evidence, distinct from merely published content.
-- Existing manually scheduled lessons may remain visible through the legacy gate;
-- never rewrite or synthesize approval hashes to force migration.
select 'scheduled_without_strict_approval_evidence' metric,count(*)::bigint value
from public.cq_v4_lesson_schedule s
where not exists (
 select 1 from public.cq_v4_activities act
 join public.cq_v4_approval_requests ar
  on ar.id=act.approval_id and ar.parent_user_id=s.parent_user_id
  and ar.chapter_uuid=s.chapter_id and ar.content_hash=act.approval_hash
 where act.chapter_uuid=s.chapter_id and act.published_at is not null
  and act.approval_hash ~ '^([0-9a-f]{32}|[0-9a-f]{64})$'
);

-- Existing future lessons already armed by legacy release flag.
-- The current cq_v4_is_released gate still prevents early student access.
select 'future_scheduled_lessons' metric,count(*)::bigint value
 from public.cq_v4_lesson_schedule
 where lesson_date >= (now() at time zone 'Asia/Seoul')::date
union all select 'future_scheduled_prearmed',count(*)::bigint
 from public.cq_v4_lesson_schedule
 where lesson_date >= (now() at time zone 'Asia/Seoul')::date
   and released_at is not null
union all select 'published_with_matching_approval_request',count(*)::bigint
 from public.cq_v4_activities a
 join public.cq_v4_approval_requests r
  on r.id=a.approval_id and r.content_hash=a.approval_hash
 where a.published_at is not null;

-- Opening week aggregate coverage only; do not infer student identity from dates.
-- 2026-11-23..29 is the first target week.
select lesson_date,extract(isodow from lesson_date)::integer as iso_weekday,
 count(*)::bigint as scheduled_students,
 count(*) filter(where released_at is not null)::bigint as prearmed_students
from public.cq_v4_lesson_schedule
where lesson_date between date '2026-11-23' and date '2026-11-29'
group by lesson_date order by lesson_date;
