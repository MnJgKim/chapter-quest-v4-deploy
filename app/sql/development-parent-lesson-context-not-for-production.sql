-- DEVELOPMENT ONLY. Read-only parent lesson context for objective reread warnings.
-- Do not execute against production without separate explicit approval.
create or replace function public.cq_v4_parent_lesson(p_chapter_uuid uuid)
returns table(questions jsonb,answer_key jsonb)
language sql stable security definer set search_path=''
as $fn$
 select a.questions,r.answer_key
 from public.cq_v4_activities a
 join public.cq_v4_approval_requests r
   on r.id=a.approval_id
  and r.chapter_uuid=a.chapter_uuid
  and r.content_hash=a.approval_hash
 join public.cq_v4_pdf_chapters c on c.chapter_id=a.chapter_uuid
 where a.chapter_uuid=p_chapter_uuid
   and a.published_at is not null
   and c.parent_user_id=(select auth.uid())
   and public.cq_is_admin()
   and jsonb_typeof(a.questions)='array'
   and jsonb_typeof(r.questions)='array'
   and a.questions=r.questions
   and jsonb_typeof(r.answer_key)='array'
   and jsonb_array_length(a.questions)=jsonb_array_length(r.answer_key)
$fn$;
revoke all on function public.cq_v4_parent_lesson(uuid) from public,anon;
grant execute on function public.cq_v4_parent_lesson(uuid) to authenticated;
