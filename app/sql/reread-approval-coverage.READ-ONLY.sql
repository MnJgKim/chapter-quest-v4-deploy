-- Read-only production preflight for reread scoring. Never backfill approval_id automatically.
SELECT count(*) AS published_total,
 count(*) FILTER (WHERE a.approval_id IS NULL) AS missing_approval_id,
 count(*) FILTER (WHERE a.approval_id IS NOT NULL AND r.id IS NULL) AS orphan_approval_id,
 count(*) FILTER (WHERE r.id IS NOT NULL AND r.chapter_uuid IS DISTINCT FROM a.chapter_uuid) AS chapter_mismatch,
 count(*) FILTER (WHERE r.id IS NOT NULL AND r.content_hash IS DISTINCT FROM a.approval_hash) AS hash_mismatch,
 count(*) FILTER (WHERE r.id IS NOT NULL AND r.chapter_uuid=a.chapter_uuid AND r.content_hash=a.approval_hash) AS verified
FROM public.cq_v4_activities a
LEFT JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id
WHERE a.published_at IS NOT NULL;
-- The 2026-11-19 read-only production check returned 11 total, 9 missing IDs, 2 verified.
-- A missing approval record means server scoring must be skipped, not inferred.
