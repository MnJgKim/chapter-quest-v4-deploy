-- DEVELOPMENT ONLY. Exact restoration of existing approved questions, not a new approval.
-- Run only after separate production authorization and successful isolated testing.
create or replace function public.cq_v4_restore_approved_questions(
 p_chapter_uuid uuid, p_approval_id uuid, p_approval_hash text
) returns uuid language plpgsql security definer set search_path=''
as $fn$
declare v_uid uuid:=auth.uid(); v_req public.cq_v4_approval_requests%rowtype;
 v_act public.cq_v4_activities%rowtype; v_hash text;
begin
 if v_uid is null or not public.cq_is_admin() then
   raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_chapter_uuid is null or p_approval_id is null or p_approval_hash is null then
   raise exception 'Missing identifier' using errcode='22023';
 end if;
 -- This lock must also be acquired FOR SHARE by the submit RPC before reading questions.
 perform 1 from public.cq_v4_pdf_chapters
  where chapter_id=p_chapter_uuid and parent_user_id=v_uid for update;
 if not found then raise exception 'Chapter not owned' using errcode='42501'; end if;
 select * into v_req from public.cq_v4_approval_requests
  where id=p_approval_id and parent_user_id=v_uid and chapter_uuid=p_chapter_uuid for update;
 if not found or v_req.content_hash is distinct from p_approval_hash then
   raise exception 'Approved request mismatch' using errcode='42501';
 end if;
 v_hash:=md5(jsonb_build_array(v_req.book_local_id,v_req.chapter_local_id,
 v_req.title,v_req.source_text,v_req.questions,v_req.answer_key,
 v_req.vocabulary,v_req.writing_prompt,v_req.speaking_prompt)::text);
 if v_hash is distinct from v_req.content_hash then
   raise exception 'Approval payload hash mismatch' using errcode='23514';
 end if;
 if jsonb_typeof(v_req.questions)<>'array' or jsonb_typeof(v_req.answer_key)<>'array'
 or jsonb_array_length(v_req.questions)<>jsonb_array_length(v_req.answer_key) then
   raise exception 'Approved questions/keys mismatch' using errcode='22023';
 end if;
 select * into v_act from public.cq_v4_activities
  where chapter_uuid=p_chapter_uuid for update;
 if not found or v_act.published_at is null or v_act.approval_id is distinct from p_approval_id
 or v_act.approval_hash is distinct from p_approval_hash then
   raise exception 'Publication changed' using errcode='40001';
 end if;
 if exists(select 1 from public.cq_v4_student_submissions where chapter_uuid=p_chapter_uuid) then
   raise exception 'Existing submission blocks correction' using errcode='23505';
 end if;
 -- No-op is safe; do not modify approval history or assignments.
 if v_act.questions is distinct from v_req.questions
    or v_act.vocabulary is distinct from v_req.vocabulary
    or v_act.writing_prompt is distinct from v_req.writing_prompt
    or v_act.speaking_prompt is distinct from v_req.speaking_prompt then
   update public.cq_v4_activities set
    questions=v_req.questions,vocabulary=v_req.vocabulary,
    writing_prompt=v_req.writing_prompt,speaking_prompt=v_req.speaking_prompt
   where chapter_uuid=p_chapter_uuid;
 end if;
 return p_chapter_uuid;
end;
$fn$;
revoke all on function public.cq_v4_restore_approved_questions(uuid,uuid,text) from public,anon;
grant execute on function public.cq_v4_restore_approved_questions(uuid,uuid,text) to authenticated;
