-- READ ONLY: first-lesson readiness and Seoul-date release gate audit.
-- Does not invoke any scheduler or modify student data.
SELECT s.lesson_date, s.timezone, c.title AS chapter_title,
       c.pdf_ready, a.published_at IS NOT NULL AS activity_published,
       EXISTS(SELECT 1 FROM public.cq_v4_pdf_assignments x
              WHERE x.chapter_id=s.chapter_id AND x.student_user_id=s.student_user_id) AS assigned,
       EXISTS(SELECT 1 FROM public.cq_v4_pdf_enrollments e
              WHERE e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id) AS enrolled,
       s.released_at IS NOT NULL AS release_flag,
       (now() AT TIME ZONE COALESCE(NULLIF(s.timezone,''),'Asia/Seoul'))::date >= s.lesson_date AS lesson_date_gate_open,
       (SELECT i.student_name FROM public.cq_v4_invites i
        WHERE i.claimed_by=s.student_user_id ORDER BY i.created_at DESC LIMIT 1) AS invite_student_name
FROM public.cq_v4_lesson_schedule s
JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
LEFT JOIN public.cq_v4_activities a ON a.chapter_uuid=s.chapter_id
WHERE s.lesson_date IN (DATE '2026-11-23',DATE '2026-11-24')
ORDER BY s.lesson_date,c.title;
