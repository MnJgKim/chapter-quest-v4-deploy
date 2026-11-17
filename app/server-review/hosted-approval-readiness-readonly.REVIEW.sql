-- REVIEW ONLY. READ ONLY. Aggregate approval readiness without exposing student identities.
-- A published activity is not equivalent to a verifiably approved activity.
WITH published AS (
 SELECT a.chapter_uuid,a.approval_id,a.approval_hash,
        EXISTS (SELECT 1 FROM public.cq_v4_approval_requests r
                WHERE r.id=a.approval_id AND r.chapter_uuid=a.chapter_uuid
                  AND r.content_hash=a.approval_hash) AS matches_approval
 FROM public.cq_v4_activities a WHERE a.published_at IS NOT NULL
), status AS (
 SELECT chapter_uuid,
        (approval_hash ~ '^[0-9a-f]{32}$' OR approval_hash ~ '^[0-9a-f]{64}$') AS hash_format_ok,
        matches_approval
 FROM published
)
SELECT count(*) AS published_chapters,
       count(*) FILTER (WHERE matches_approval AND hash_format_ok) AS verified_approval_chapters,
       count(*) FILTER (WHERE NOT(coalesce(matches_approval,false) AND coalesce(hash_format_ok,false))) AS approval_review_required
FROM status;
-- No INSERT/UPDATE/DELETE. This does not grant approvals or rewrite published lessons.
