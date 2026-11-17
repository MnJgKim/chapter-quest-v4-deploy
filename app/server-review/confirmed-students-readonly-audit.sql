-- Read-only audit of the confirmed student accounts. Does not modify user identities.
-- Prefixes are diagnostic only; never use a UUID prefix as an authorization rule.
WITH seowoo AS (
 SELECT s.student_user_id,s.parent_user_id FROM public.cq_v4_lesson_schedule s
 WHERE left(s.student_user_id::text,8)='b7c90ec0' GROUP BY 1,2
), seojin AS (
 SELECT i.claimed_by AS student_user_id,i.parent_user_id
 FROM public.cq_v4_invites i
 WHERE i.student_name='서진' AND i.approved_at IS NOT NULL AND i.revoked_at IS NULL AND i.claimed_by IS NOT NULL
), students AS (
 SELECT '서우' AS student_name,student_user_id,parent_user_id FROM seowoo
 UNION ALL SELECT '서진',student_user_id,parent_user_id FROM seojin
)
SELECT x.student_name,
 COUNT(DISTINCT e.student_user_id) AS enrolled,
 COUNT(DISTINCT a.chapter_id) AS assigned,
 COUNT(DISTINCT s.chapter_id) AS scheduled,
 COUNT(DISTINCT s.chapter_id) FILTER(WHERE s.released_at IS NOT NULL) AS flagged_for_release,
 COUNT(DISTINCT sub.chapter_uuid) AS submitted,
 COUNT(DISTINCT s.chapter_id) FILTER(WHERE s.lesson_date=(CASE WHEN x.student_name='서우' THEN DATE '2026-11-23' ELSE DATE '2026-11-24' END)) AS first_lesson_assigned
FROM students x
LEFT JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=x.student_user_id AND e.parent_user_id=x.parent_user_id
LEFT JOIN public.cq_v4_pdf_assignments a ON a.student_user_id=x.student_user_id
LEFT JOIN public.cq_v4_lesson_schedule s ON s.student_user_id=x.student_user_id AND s.parent_user_id=x.parent_user_id
LEFT JOIN public.cq_v4_student_submissions sub ON sub.child_user_id=x.student_user_id
GROUP BY x.student_name ORDER BY x.student_name;
