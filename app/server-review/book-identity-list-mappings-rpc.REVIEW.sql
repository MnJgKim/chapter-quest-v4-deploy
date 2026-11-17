-- REVIEW ONLY. Parent-only mapping read for existing PDF chapter records.
create or replace function public.cq_v4_parent_list_book_chapters()
returns table(chapter_id uuid,book_id uuid,chapter_number integer)
language plpgsql security definer set search_path=''
as $fn$
begin
 if auth.uid() is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 return query
 select bc.chapter_id,bc.book_id,bc.chapter_number
 from public.cq_v4_book_chapters bc
 join public.cq_v4_books b on b.book_id=bc.book_id and b.parent_user_id=bc.parent_user_id
 where bc.parent_user_id=auth.uid()
 order by bc.book_id,bc.chapter_number;
end $fn$;
revoke all on function public.cq_v4_parent_list_book_chapters() from public,anon;
grant execute on function public.cq_v4_parent_list_book_chapters() to authenticated;
