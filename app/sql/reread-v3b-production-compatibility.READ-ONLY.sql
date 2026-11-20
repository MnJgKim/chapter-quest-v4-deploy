-- READ ONLY. V3B production compatibility audit; no mutation.
-- Do not display answer keys or student answers in reports.
WITH published AS (
 SELECT a.chapter_uuid,a.approval_id,a.approval_hash,a.questions,
        r.id AS matched_approval_id
 FROM public.cq_v4_activities a
 LEFT JOIN public.cq_v4_approval_requests r
   ON r.id=a.approval_id AND r.chapter_uuid=a.chapter_uuid
  AND r.content_hash=a.approval_hash AND r.questions=a.questions
  AND jsonb_typeof(r.answer_key)='array'
  AND jsonb_array_length(r.answer_key)=jsonb_array_length(a.questions)
 WHERE a.published_at IS NOT NULL
)
SELECT count(*) AS published_chapters,
 count(*) FILTER (WHERE matched_approval_id IS NOT NULL) AS snapshot_ready,
 count(*) FILTER (WHERE matched_approval_id IS NULL) AS requires_approval_reconciliation
FROM published;
-- Before activation: snapshot_ready must include EVERY chapter scheduled for
-- new submissions; never backfill missing approvals from guesses or live answers.
