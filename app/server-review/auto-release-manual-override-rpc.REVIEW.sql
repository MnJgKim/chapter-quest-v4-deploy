-- REVIEW ONLY. Explicit manual parent release takes precedence over automatic arms.
-- Install only after backup, compatibility verification, and parent approval.
-- Depends on existing cq_v4_parent_set_lesson_release and auto-release tables.
create or replace function public.cq_v4_parent_override_lesson_release(
 p_student_user_id uuid,p_chapter_id uuid,p_release boolean
) returns void language plpgsql security definer set search_path=''
as $fn$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_student_user_id is null or p_chapter_id is null or p_release is null then
  raise exception 'Student, chapter and release flag required' using errcode='22023';
 end if;
 -- Serialize with automatic scheduling, cancellation and policy changes.
 perform 1 from public.cq_v4_pdf_enrollments
 where parent_user_id=v_parent and student_user_id=p_student_user_id for update;
 if not found then raise exception 'Student enrollment required' using errcode='42501';end if;
 -- Closing a submitted lesson must not hide completed work or feedback.
 if not p_release and exists(select 1 from public.cq_v4_student_submissions
  where child_user_id=p_student_user_id and chapter_uuid=p_chapter_id) then
  raise exception 'Submitted lesson cannot be hidden' using errcode='42501';
 end if;
 if not p_release and exists(select 1 from public.cq_v4_student_submissions
   where child_user_id=p_student_user_id and chapter_uuid=p_chapter_id)
 then raise exception 'Submitted lesson cannot be hidden' using errcode='42501';end if;
 -- Existing RPC remains the authorization and approval-evidence gate.
 perform public.cq_v4_parent_set_lesson_release(p_student_user_id,p_chapter_id,p_release);
 -- Explicit manual action supersedes the automatic release origin.
 update public.cq_v4_auto_release_arms set revoked_at=now()
 where parent_user_id=v_parent and student_user_id=p_student_user_id
   and chapter_id=p_chapter_id and revoked_at is null;
 if not p_release then
  -- Prevent a later automatic planner run from silently re-opening it.
  insert into public.cq_v4_auto_release_cancellations
   (parent_user_id,student_user_id,chapter_id)
  values(v_parent,p_student_user_id,p_chapter_id)
  on conflict(student_user_id,chapter_id) do nothing;
 end if;
end $fn$;
revoke all on function public.cq_v4_parent_override_lesson_release(uuid,uuid,boolean) from public,anon;
grant execute on function public.cq_v4_parent_override_lesson_release(uuid,uuid,boolean) to authenticated;
