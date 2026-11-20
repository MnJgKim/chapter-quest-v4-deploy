-- READ ONLY: Chapter Quest V4 automatic release deployment preflight.
-- No production data changes. Run before approving the REVIEW-ONLY migration.
WITH required_objects AS (
  SELECT 'table' AS kind, 'cq_v4_lesson_schedule' AS name UNION ALL
  SELECT 'table','cq_v4_student_weekday_policy' UNION ALL
  SELECT 'table','cq_v4_approved_chapter_queue' UNION ALL
  SELECT 'function','cq_v4_ensure_today_approved_lesson' UNION ALL
  SELECT 'function','cq_v4_next_approved_chapter'
), objects AS (
  SELECT kind,name,
    CASE WHEN kind='table' THEN to_regclass('public.'||name) IS NOT NULL
    ELSE EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=name) END AS installed
  FROM required_objects
)
SELECT kind,name,installed FROM objects ORDER BY kind,name;

-- Detect conflicts that would make one-chapter-per-day automation unsafe.
SELECT student_user_id,lesson_date,COUNT(*) AS conflicting_rows
FROM public.cq_v4_lesson_schedule
GROUP BY student_user_id,lesson_date HAVING COUNT(*)>1;

-- Verify every scheduled lesson has the published PDF, approved activity and assignment.
SELECT s.lesson_date,s.chapter_id,
  (c.chapter_id IS NOT NULL AND c.pdf_ready IS TRUE) AS pdf_ready,
  (a.chapter_uuid IS NOT NULL AND a.published_at IS NOT NULL) AS published_activity,
  (x.chapter_id IS NOT NULL) AS assigned,
  (e.student_user_id IS NOT NULL) AS enrolled,
  (s.timezone='Asia/Seoul') AS seoul_timezone,
  (s.released_at IS NOT NULL) AS release_flag
FROM public.cq_v4_lesson_schedule s
LEFT JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id
  AND c.parent_user_id=s.parent_user_id
LEFT JOIN public.cq_v4_activities a ON a.chapter_uuid=s.chapter_id
LEFT JOIN public.cq_v4_pdf_assignments x ON x.chapter_id=s.chapter_id
  AND x.student_user_id=s.student_user_id
LEFT JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=s.student_user_id
  AND e.parent_user_id=s.parent_user_id
WHERE s.lesson_date BETWEEN DATE '2026-11-23' AND DATE '2026-12-14'
ORDER BY s.lesson_date,s.chapter_id;
