-- REVIEW ONLY. Parent-only read of enrolled students' automatic-release policies.
create or replace function public.cq_v4_parent_list_auto_release_policies()
returns table(student_user_id uuid,enabled boolean,weekdays smallint[])
language plpgsql security definer set search_path=''
as $fn$
begin
 if auth.uid() is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 return query
 select e.student_user_id,coalesce(p.enabled,false),
  coalesce(p.weekdays,'{}'::smallint[])
 from public.cq_v4_pdf_enrollments e
 left join public.cq_v4_auto_release_policies p
  on p.parent_user_id=e.parent_user_id and p.student_user_id=e.student_user_id
 where e.parent_user_id=auth.uid()
 order by e.student_user_id;
end $fn$;
revoke all on function public.cq_v4_parent_list_auto_release_policies() from public,anon;
grant execute on function public.cq_v4_parent_list_auto_release_policies() to authenticated;
