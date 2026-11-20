-- Chapter Quest V4: first lesson account and content prerequisites.
-- SELECT only. Never identifies a child by guessing from a schedule date.
WITH approved AS (
 SELECT i.student_name,i.claimed_by AS student_user_id,i.parent_user_id
 FROM public.cq_v4_invites i
 WHERE i.student_name IN ('서우','서진')
   AND i.claimed_by IS NOT NULL
   AND i.approved_at IS NOT NULL AND i.revoked_at IS NULL
), targets(student_name,first_date) AS (
 VALUES ('서우',DATE '2026-11-23'),('서진',DATE '2026-11-24')
)
SELECT t.student_name,t.first_date,
       COUNT(DISTINCT a.student_user_id) AS approved_accounts,
       COUNT(DISTINCT e.student_user_id) AS enrolled_accounts,
       COUNT(DISTINCT p.chapter_id) AS assigned_chapters,
       COUNT(DISTINCT s.chapter_id) FILTER (WHERE s.lesson_date=t.first_date) AS first_date_chapters,
       COUNT(DISTINCT s.chapter_id) FILTER (WHERE s.lesson_date=t.first_date AND s.released_at IS NOT NULL) AS first_date_release_flags
FROM targets t
LEFT JOIN approved a ON a.student_name=t.student_name
LEFT JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=a.student_user_id AND e.parent_user_id=a.parent_user_id
LEFT JOIN public.cq_v4_pdf_assignments p ON p.student_user_id=a.student_user_id
LEFT JOIN public.cq_v4_lesson_schedule s ON s.student_user_id=a.student_user_id AND s.parent_user_id=a.parent_user_id
GROUP BY t.student_name,t.first_date
ORDER BY t.first_date;
