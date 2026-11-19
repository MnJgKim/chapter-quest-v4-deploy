-- Chapter Quest V4: READ ONLY. No deletions, updates, or billing changes.
-- Size comes from storage.objects metadata; it does not represent project-wide billing usage.
-- A shared chapter can have several student assignments without duplicating the PDF object.
WITH chapter_usage AS (
 SELECT c.chapter_id,c.title,c.storage_path,c.pdf_ready,
        count(DISTINCT a.student_user_id) AS assigned_students,
        count(DISTINCT s.child_user_id) AS submitted_students,
        count(DISTINCT a.student_user_id) > 0 AS has_active_assignment
 FROM public.cq_v4_pdf_chapters c
 LEFT JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 LEFT JOIN public.cq_v4_student_submissions s ON s.chapter_uuid=c.chapter_id
 GROUP BY c.chapter_id,c.title,c.storage_path,c.pdf_ready
), object_usage AS (
 SELECT o.name,o.bucket_id,
        CASE WHEN (o.metadata->>'size') ~ '^[0-9]+$' THEN (o.metadata->>'size')::numeric ELSE NULL END AS size_bytes
 FROM storage.objects o WHERE o.bucket_id='cq-v4-originals'
)
SELECT u.chapter_id,u.title,u.pdf_ready,u.assigned_students,u.submitted_students,
       o.bucket_id,round(o.size_bytes/1048576,2) AS size_mib,
       CASE WHEN o.name IS NULL THEN 'MISSING_OBJECT'
            WHEN u.assigned_students>u.submitted_students THEN 'KEEP_UNFINISHED_OR_FUTURE_USE'
            WHEN u.assigned_students>0 THEN 'REVIEW_ONLY_COMPLETED_CHECK_HISTORY'
            ELSE 'REVIEW_ONLY_UNASSIGNED_CHECK_HISTORY' END AS review_status
FROM chapter_usage u LEFT JOIN object_usage o ON o.name=u.storage_path
ORDER BY review_status,u.title;

-- Count every object once, including orphaned objects not referenced by chapter rows.
SELECT count(*) AS stored_objects,
       round(sum(CASE WHEN (metadata->>'size') ~ '^[0-9]+$' THEN (metadata->>'size')::numeric ELSE 0 END)/1048576,2) AS stored_mib
FROM storage.objects WHERE bucket_id='cq-v4-originals';

-- IMPORTANT: review_status is NOT deletion authorization. Never auto-delete:
-- submitted answers, snapshots, historical PDF access, future student reuse,
-- parental consent, and storage/billing limits require separate verification.
