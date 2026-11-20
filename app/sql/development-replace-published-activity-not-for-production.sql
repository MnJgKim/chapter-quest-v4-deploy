-- DEVELOPMENT ONLY. Never run against production without explicit approval.
-- Replace published learning content IN PLACE; preserve chapter UUID, PDF,
-- assignments, historical approval, submissions and immutable snapshots.
create or replace function public.cq_v4_replace_published_activity(
 p_chapter_uuid uuid, p_old_approval_id uuid, p_old_approval_hash text,
 p_new_approval_id uuid
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid := auth.uid();
 v_old public.cq_v4_activities%rowtype;
 v_new public.cq_v4_approval_requests%rowtype;
 v_chapter public.cq_v4_pdf_chapters%rowtype;
 v_i integer; v_q jsonb; v_answer jsonb; v_expected_hash text;
begin
 if v_uid is null or not public.cq_is_admin() then
   raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_chapter_uuid is null or p_old_approval_id is null
    or p_old_approval_hash is null or p_new_approval_id is null
    or p_old_approval_id=p_new_approval_id then
   raise exception 'Invalid replacement identifiers' using errcode='22023';
 end if;
 -- FOR UPDATE conflicts with FK KEY SHARE during concurrent submissions.
 -- It serializes this replacement with submissions and other replacements.
 select * into v_chapter from public.cq_v4_pdf_chapters
  where chapter_id=p_chapter_uuid and parent_user_id=v_uid
    and pdf_ready is true and pdf_verified_at is not null
    and nullif(pg_catalog.btrim(storage_path),'') is not null
  for update;
 if not found then raise exception 'Verified owned chapter required' using errcode='42501'; end if;
 select * into v_old from public.cq_v4_activities
  where chapter_uuid=p_chapter_uuid for update;
 if not found or v_old.published_at is null
    or v_old.approval_id is distinct from p_old_approval_id
    or v_old.approval_hash is distinct from p_old_approval_hash then
   raise exception 'Published approval changed; refresh before replacement' using errcode='40001';
 end if;
 if not exists(select 1 from public.cq_v4_approval_requests old_req
               where old_req.id=p_old_approval_id
                 and old_req.chapter_uuid=p_chapter_uuid
                 and old_req.parent_user_id=v_uid
                 and old_req.content_hash=p_old_approval_hash) then
   raise exception 'Previous approval record does not match' using errcode='42501';
 end if;
 -- Recheck after lock; never replace content with an existing submission.
 if exists(select 1 from public.cq_v4_student_submissions
           where chapter_uuid=p_chapter_uuid) then
   raise exception 'Existing submission prevents replacement' using errcode='23505';
 end if;
 select * into v_new from public.cq_v4_approval_requests
  where id=p_new_approval_id and parent_user_id=v_uid for update;
 if not found or (v_new.chapter_uuid is not null and v_new.chapter_uuid<>p_chapter_uuid)
    or v_new.content_hash is null then
   raise exception 'Fresh owned approval required' using errcode='42501';
 end if;
 -- The registration RPC hashes the complete payload; reject modified approval rows.
 v_expected_hash:=pg_catalog.md5(pg_catalog.jsonb_build_array(
    v_new.book_local_id,v_new.chapter_local_id,v_new.title,v_new.source_text,
    v_new.questions,v_new.answer_key,v_new.vocabulary,
    v_new.writing_prompt,v_new.speaking_prompt)::text);
 if v_new.content_hash is distinct from v_expected_hash then
   raise exception 'New approval content hash mismatch' using errcode='23514';
 end if;
 if exists(select 1 from public.cq_v4_activities where approval_id=p_new_approval_id) then
   raise exception 'Approval already published' using errcode='23505';
 end if;
 if jsonb_typeof(v_new.questions)<>'array'
    or jsonb_typeof(v_new.answer_key)<>'array'
    or jsonb_typeof(v_new.vocabulary)<>'array'
    or jsonb_array_length(v_new.questions) not between 1 and 30
    or jsonb_array_length(v_new.questions)<>jsonb_array_length(v_new.answer_key) then
   raise exception 'Invalid replacement payload' using errcode='22023';
 end if;
 for v_i in 0..jsonb_array_length(v_new.questions)-1 loop
   v_q:=v_new.questions->v_i;
   v_answer:=v_new.answer_key->v_i;
   if v_q->>'kind'='mc' then
     if jsonb_typeof(v_q->'options')<>'array'
        or jsonb_array_length(v_q->'options') not between 2 and 6
        or jsonb_typeof(v_answer)<>'number'
        or (v_answer #>> '{}') !~ '^(0|[1-9][0-9]*)$'
        or (v_answer #>> '{}')::integer>=jsonb_array_length(v_q->'options') then
       raise exception 'Invalid approved MC answer' using errcode='22023';
     end if;
   elsif v_q->>'kind' in ('short','inference','critical','comprehension') then
     if jsonb_typeof(v_answer)<>'string' or nullif(pg_catalog.btrim(v_answer #>> '{}'),'') is null then
       raise exception 'Non-MC answer key must be a nonempty sample string' using errcode='22023';
     end if;
   else
     raise exception 'Invalid question kind' using errcode='22023';
   end if;
 end loop;
 -- Chapter 2 minimal-correction scope: preserve all ten published questions,
 -- vocabulary and prompts. The seventh MC key must be Red (zero-based 1).
 -- Existing six approved keys must remain unchanged.
 if p_chapter_uuid='8fe27ea2-b1ce-4404-a5bf-75b5a049a38a'::uuid then
   if jsonb_array_length(v_new.questions)<>10
      or v_new.questions is distinct from v_old.questions
      or v_new.vocabulary is distinct from v_old.vocabulary
      or v_new.writing_prompt is distinct from v_old.writing_prompt
      or v_new.speaking_prompt is distinct from v_old.speaking_prompt
      or v_new.answer_key->6 is distinct from '1'::jsonb
      or exists(
        select 1 from public.cq_v4_approval_requests prior
        where prior.id=p_old_approval_id
          and (
            jsonb_array_length(prior.answer_key)<>6
            or v_new.answer_key->0 is distinct from prior.answer_key->0
            or v_new.answer_key->1 is distinct from prior.answer_key->1
            or v_new.answer_key->2 is distinct from prior.answer_key->2
            or v_new.answer_key->3 is distinct from prior.answer_key->3
            or v_new.answer_key->4 is distinct from prior.answer_key->4
            or v_new.answer_key->5 is distinct from prior.answer_key->5
          )
      ) then
     raise exception 'Chapter 2 correction must preserve all 10 questions and prior six keys'
       using errcode='23514';
   end if;
 end if;
 -- Existing approval row remains unchanged; the new approval becomes bound.
 update public.cq_v4_approval_requests set chapter_uuid=p_chapter_uuid
  where id=p_new_approval_id;
 update public.cq_v4_activities set
   questions=v_new.questions, vocabulary=v_new.vocabulary,
   writing_prompt=v_new.writing_prompt, speaking_prompt=v_new.speaking_prompt,
   approval_id=v_new.id, approval_hash=v_new.content_hash,
   published_at=now()
 where chapter_uuid=p_chapter_uuid;
 return p_chapter_uuid;
end;
$function$;
revoke all on function public.cq_v4_replace_published_activity(uuid,uuid,text,uuid)
 from public,anon;
grant execute on function public.cq_v4_replace_published_activity(uuid,uuid,text,uuid)
 to authenticated;

-- INTEGRATION TESTS REQUIRED before deployment:
-- Parent owns chapter and fresh approval; no submissions; old ID/hash exact;
-- 10 questions with 10 aligned key entries (non-MC samples are strings);
-- repeat request rejected; other parent rejected; submitted chapter rejected;
-- concurrent submit vs replace serialized; invalid key rolls back approval bind;
-- chapter UUID, PDF path, 2 assignments and old approval remain unchanged;
-- single activity row after replacement; student sees only one chapter.
