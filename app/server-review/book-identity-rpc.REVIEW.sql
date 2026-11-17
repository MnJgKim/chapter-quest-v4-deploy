-- REVIEW ONLY. Parent-only book listing; not deployed.
create or replace function public.cq_v4_parent_list_books()
returns table(book_id uuid,title text,chapter_count bigint)
language plpgsql security definer set search_path=''
as $fn$
begin
 if auth.uid() is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 return query
 select b.book_id,b.title,count(bc.chapter_id)::bigint
 from public.cq_v4_books b
 left join public.cq_v4_book_chapters bc on bc.book_id=b.book_id and bc.parent_user_id=b.parent_user_id
 where b.parent_user_id=auth.uid()
 group by b.book_id,b.title
 order by b.title,b.book_id;
end $fn$;
revoke all on function public.cq_v4_parent_list_books() from public,anon;
grant execute on function public.cq_v4_parent_list_books() to authenticated;

-- REVIEW ONLY. Explicit book creation; title alone never implies an existing book.
create or replace function public.cq_v4_parent_create_book(p_title text)
returns uuid language plpgsql security definer set search_path=''
as $fn$
declare v_id uuid;
begin
 if auth.uid() is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_title is null or length(btrim(p_title)) not between 1 and 300 then
  raise exception 'Invalid book title' using errcode='22023';
 end if;
 insert into public.cq_v4_books(parent_user_id,title) values(auth.uid(),btrim(p_title)) returning book_id into v_id;
 return v_id;
end $fn$;
revoke all on function public.cq_v4_parent_create_book(text) from public,anon;
grant execute on function public.cq_v4_parent_create_book(text) to authenticated;

-- REVIEW ONLY. Existing PDF is linked, not copied, overwritten, or deleted.
create or replace function public.cq_v4_parent_link_book_chapter(
 p_book_id uuid,p_chapter_id uuid,p_chapter_number integer
) returns void language plpgsql security definer set search_path=''
as $fn$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_book_id is null or p_chapter_id is null or p_chapter_number is null
    or p_chapter_number not between 1 and 10000 then
  raise exception 'Invalid chapter link' using errcode='22023';
 end if;
 perform 1 from public.cq_v4_books
 where book_id=p_book_id and parent_user_id=v_parent for update;
 if not found then raise exception 'Owned book required' using errcode='42501';end if;
 perform 1 from public.cq_v4_pdf_chapters
 where chapter_id=p_chapter_id and parent_user_id=v_parent for update;
 if not found then raise exception 'Owned chapter required' using errcode='42501';end if;
 if exists(select 1 from public.cq_v4_book_chapters where chapter_id=p_chapter_id) then
  raise exception 'Chapter already linked; explicit move is not supported' using errcode='23505';
 end if;
 insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number)
 values(p_chapter_id,p_book_id,v_parent,p_chapter_number);
end $fn$;
revoke all on function public.cq_v4_parent_link_book_chapter(uuid,uuid,integer) from public,anon;
grant execute on function public.cq_v4_parent_link_book_chapter(uuid,uuid,integer) to authenticated;

-- REVIEW ONLY. Parent-scoped mapping list for avoiding duplicate links in the UI.
create or replace function public.cq_v4_parent_list_book_chapters()
returns table(book_id uuid,chapter_id uuid,chapter_number integer)
language plpgsql security definer set search_path=''
as $fn$
begin
 if auth.uid() is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 return query
 select bc.book_id,bc.chapter_id,bc.chapter_number
 from public.cq_v4_book_chapters bc
 where bc.parent_user_id=auth.uid()
 order by bc.book_id,bc.chapter_number;
end $fn$;
revoke all on function public.cq_v4_parent_list_book_chapters() from public,anon;
grant execute on function public.cq_v4_parent_list_book_chapters() to authenticated;
