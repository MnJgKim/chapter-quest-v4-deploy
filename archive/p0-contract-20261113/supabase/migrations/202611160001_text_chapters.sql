-- Additive extension of the P0 chapter/assignment contract. No duplicate identity tables.
begin;
alter table public.cq_v4_chapters add column material_type text not null default 'pdf' check(material_type in ('pdf','txt'));
alter table public.cq_v4_chapters add column reading_text text;
create function public.cq_v4_register_text_chapter(p_book_id text,p_chapter_id text,p_title text,p_text text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); c public.cq_v4_chapters; begin
 if length(trim(coalesce(p_book_id,''))) not between 1 and 200 or length(trim(coalesce(p_chapter_id,''))) not between 1 and 200 or length(trim(coalesce(p_text,''))) not between 1 and 45000 then raise exception 'INVALID_TEXT_CHAPTER'; end if;
 insert into public.cq_v4_chapters(parent_user_id,book_id,chapter_id,title,material_type,reading_text,pdf_ready) values(u,p_book_id,p_chapter_id,p_title,'txt',p_text,true) on conflict(parent_user_id,book_id,chapter_id) do nothing;
 select * into c from public.cq_v4_chapters where parent_user_id=u and book_id=p_book_id and chapter_id=p_chapter_id for update;
 if c.material_type<>'txt' then raise exception 'MATERIAL_TYPE_CONFLICT'; end if;
 if c.approval_id is not null and (c.reading_text<>p_text or c.title<>p_title) then raise exception 'CHAPTER_ALREADY_PUBLISHED'; end if;
 update public.cq_v4_chapters set reading_text=p_text,title=p_title,pdf_ready=true where chapter_uuid=c.chapter_uuid;
 return c.chapter_uuid;
end $$;
-- pdf_ready is retained as the legacy material-readiness flag used by existing can_read/publication RPCs.
-- TXT is readable only after parent publication and explicit student assignment, just like PDF.
create function cq_private.guard_text_publication() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.material_type='txt' and new.approval_id is not null and new.source is distinct from new.reading_text then raise exception 'TEXT_APPROVAL_MISMATCH'; end if;
 return new;
end $$;
create trigger cq_v4_text_publication before update on public.cq_v4_chapters for each row execute function cq_private.guard_text_publication();
create function public.cq_v4_my_reading(p_chapter_uuid uuid) returns table(material_type text,reading_text text) language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); begin
 if not cq_private.can_read(p_chapter_uuid,u) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return query select c.material_type,case when c.material_type='txt' then c.reading_text else null end from public.cq_v4_chapters c where c.chapter_uuid=p_chapter_uuid;
end $$;
revoke all on function cq_private.guard_text_publication() from public,anon,authenticated;
revoke all on function public.cq_v4_register_text_chapter(text,text,text,text),public.cq_v4_my_reading(uuid) from public,anon;
grant execute on function public.cq_v4_register_text_chapter(text,text,text,text),public.cq_v4_my_reading(uuid) to authenticated;
commit;
