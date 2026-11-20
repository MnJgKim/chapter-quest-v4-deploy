-- READ ONLY: detect published chapters whose approved answer keys cannot be scored.
-- Run only SELECT statements; never reveal answer keys to student clients.
select a.chapter_uuid,
       jsonb_array_length(a.questions) as published_questions,
       jsonb_array_length(req.answer_key) as approved_answers,
       (a.approval_hash=req.content_hash) as hash_matches
from public.cq_v4_activities a
join public.cq_v4_approval_requests req
  on req.id=a.approval_id and req.chapter_uuid=a.chapter_uuid
where a.published_at is not null
  and (jsonb_typeof(req.answer_key)<>'array'
       or jsonb_array_length(a.questions)<>jsonb_array_length(req.answer_key)
       or a.approval_hash is distinct from req.content_hash);
-- Deployment BLOCKER: currently one published chapter has 10 questions but 6
-- approved answer entries. Resolve the answer-key mapping without altering
-- existing student submissions before enabling the after-insert scoring trigger.
