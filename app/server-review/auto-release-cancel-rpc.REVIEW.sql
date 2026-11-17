-- REVIEW ONLY. Parent cancellation of automatic release; never deploy without approval.
-- A tombstone is durable. Explicit re-authorization must be a separate action.
create or replace function public.cq_v4_parent_cancel_auto_release(
 p_student_user_id uuid,p_chapter_id uuid
) returns void language plpgsql security definer set search_path=''
as $fn$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_student_user_id is null or p_chapter_id is null then
  raise exception 'Student and chapter required' using errcode='22023';
 end if;
 perform 1 from public.cq_v4_pdf_enrollments
 where parent_user_id=v_parent and student_user_id=p_student_user_id for update;
 if not found then raise exception 'Student enrollment required' using errcode='42501';end if;
 if not exists(select 1 from public.cq_v4_pdf_chapters
  where chapter_id=p_chapter_id and parent_user_id=v_parent)
 then raise exception 'Owned chapter required' using errcode='42501';end if;
 insert into public.cq_v4_auto_release_cancellations
  (parent_user_id,student_user_id,chapter_id)
 values(v_parent,p_student_user_id,p_chapter_id)
 on conflict(student_user_id,chapter_id) do nothing;
 -- A submitted lesson is immutable: cancellation must not hide completed work.
 if exists(select 1 from public.cq_v4_student_submissions
  where child_user_id=p_student_user_id and chapter_uuid=p_chapter_id) then
  raise exception 'Submitted lesson cannot be cancelled' using errcode='42501';
 end if;
 -- Only release rows with explicit automatic origin may be revoked.
 -- Lock the arm record so concurrent cancellation and arming serialize.
 perform 1 from public.cq_v4_auto_release_arms
 where parent_user_id=v_parent and student_user_id=p_student_user_id
   and chapter_id=p_chapter_id and revoked_at is null for update;
 if found then
  update public.cq_v4_auto_release_arms set revoked_at=now()
   where parent_user_id=v_parent and student_user_id=p_student_user_id
    and chapter_id=p_chapter_id and revoked_at is null;
  update public.cq_v4_lesson_schedule set released_at=null
   where parent_user_id=v_parent and student_user_id=p_student_user_id
    and chapter_id=p_chapter_id;
 end if;
 -- Legacy manual releases have no arm record and are untouched.
end $fn$;
revoke all on function public.cq_v4_parent_cancel_auto_release(uuid,uuid) from public,anon;
grant execute on function public.cq_v4_parent_cancel_auto_release(uuid,uuid) to authenticated;
