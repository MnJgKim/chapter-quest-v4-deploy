begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('cq-v4-originals','cq-v4-originals',false,52428800,array['application/pdf']),
 ('cq-v4-speaking','cq-v4-speaking',false,10485760,array['audio/webm','audio/mp4','audio/ogg']);
-- Only the verified Edge path can finalize a PDF. Authenticated callers cannot assert readiness.
create function public.cq_v4_finalize_pdf(p_chapter_uuid uuid,p_parent_user_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare c public.cq_v4_chapters; begin
 select * into c from public.cq_v4_chapters where chapter_uuid=p_chapter_uuid and parent_user_id=p_parent_user_id for update;
 if not found or not exists(select 1 from storage.objects where bucket_id='cq-v4-originals' and name=c.pdf_path and (metadata->>'size')::bigint between 5 and 52428800 and metadata->>'mimetype'='application/pdf') then raise exception 'PDF_OBJECT_NOT_VERIFIED'; end if;
 update public.cq_v4_chapters set pdf_ready=true where chapter_uuid=c.chapter_uuid; return true;
end $$;
revoke all on function public.cq_v4_finalize_pdf(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cq_v4_finalize_pdf(uuid,uuid) to service_role;
create function public.cq_v4_audio_can_write(object_name text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c uuid; begin
 if object_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|mp4|ogg)$' then return false; end if;
 if split_part(object_name,'/',1)<>auth.uid()::text then return false; end if;
 c:=split_part(split_part(object_name,'/',2),'.',1)::uuid;
 return cq_private.can_read(c,auth.uid()) and not exists(select 1 from cq_private.submissions where child_user_id=auth.uid() and chapter_uuid=c);
 exception when invalid_text_representation then return false;
end $$;
create function public.cq_v4_audio_can_read(object_name text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c uuid; child uuid; begin
 if object_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(webm|mp4|ogg)$' then return false; end if;
 child:=split_part(object_name,'/',1)::uuid; c:=split_part(split_part(object_name,'/',2),'.',1)::uuid;
 return (auth.uid()=child and cq_private.can_read(c,child)) or exists(select 1 from public.cq_v4_chapters ch join public.cq_v4_child_access a on a.parent_user_id=ch.parent_user_id and a.child_user_id=child where ch.chapter_uuid=c and ch.parent_user_id=auth.uid());
 exception when invalid_text_representation then return false;
end $$;
revoke all on function public.cq_v4_audio_can_write(text),public.cq_v4_audio_can_read(text) from public,anon;
grant execute on function public.cq_v4_audio_can_write(text),public.cq_v4_audio_can_read(text) to authenticated;
create policy cq_audio_insert on storage.objects for insert to authenticated with check(bucket_id='cq-v4-speaking' and public.cq_v4_audio_can_write(name));
create policy cq_audio_select on storage.objects for select to authenticated using(bucket_id='cq-v4-speaking' and public.cq_v4_audio_can_read(name));
-- No browser INSERT/UPDATE/DELETE/SELECT policy for original PDFs. Edge signs after authorization.
-- No browser UPDATE/DELETE policy for audio: recorded objects cannot be overwritten.
commit;
