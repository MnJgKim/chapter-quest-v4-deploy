-- REVIEW ONLY. Parent-controlled policy update; never apply without backup/approval.
create or replace function public.cq_v4_parent_set_auto_release_policy(
 p_student_user_id uuid,p_enabled boolean,p_weekdays smallint[]
) returns void language plpgsql security definer set search_path=''
as $$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_student_user_id is null or p_enabled is null or p_weekdays is null
    or cardinality(p_weekdays)=0 or cardinality(p_weekdays)>7
    or array_position(p_weekdays,null) is not null
    or not(p_weekdays <@ array[1,2,3,4,5,6,7]::smallint[])
    or (select count(distinct d) from unnest(p_weekdays) as d)<>cardinality(p_weekdays)
 then raise exception 'Invalid weekday policy' using errcode='22023';end if;
 perform 1 from public.cq_v4_pdf_enrollments
 where parent_user_id=v_parent and student_user_id=p_student_user_id for update;
 if not found then raise exception 'Student enrollment required' using errcode='42501';end if;
 insert into public.cq_v4_auto_release_policies
 (parent_user_id,student_user_id,enabled,weekdays,updated_at)
 values(v_parent,p_student_user_id,p_enabled,p_weekdays,now())
 on conflict(parent_user_id,student_user_id)
 do update set enabled=excluded.enabled,weekdays=excluded.weekdays,updated_at=now();
end $$;
revoke all on function public.cq_v4_parent_set_auto_release_policy(uuid,boolean,smallint[]) from public,anon;
grant execute on function public.cq_v4_parent_set_auto_release_policy(uuid,boolean,smallint[]) to authenticated;
