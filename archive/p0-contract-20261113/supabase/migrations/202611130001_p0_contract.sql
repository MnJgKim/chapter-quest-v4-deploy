-- Baseline for a NEW LOCAL/TEST Supabase project. Not an upgrade of an unknown production schema.
begin;
create schema cq_private;
revoke all on schema cq_private from public;
create table public.cq_v4_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'student' check(role in ('parent','student'))
);
create function cq_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.cq_v4_profiles(user_id) values(new.id); return new; end $$;
create trigger cq_v4_new_user after insert on auth.users for each row execute function cq_private.new_user();
create table public.cq_v4_child_access (
 parent_user_id uuid not null references public.cq_v4_profiles(user_id),
 child_user_id uuid not null references public.cq_v4_profiles(user_id),
 student_name text not null check(length(student_name) between 1 and 80),
 active boolean not null default false,
 primary key(parent_user_id,child_user_id), check(parent_user_id<>child_user_id)
);
create table cq_private.invites (
 token_hash bytea primary key, parent_user_id uuid not null references public.cq_v4_profiles(user_id),
 expires_at timestamptz not null, claimed_by uuid references public.cq_v4_profiles(user_id), created_at timestamptz not null default now()
);
create table public.cq_v4_chapters (
 chapter_uuid uuid primary key default gen_random_uuid(), parent_user_id uuid not null references public.cq_v4_profiles(user_id),
 book_id text not null, chapter_id text not null, title text not null check(length(title) between 1 and 200),
 source text not null default '' check(length(source)<=45000),
 questions jsonb not null default '[]', vocabulary jsonb not null default '[]',
 writing_prompt text not null default '', speaking_prompt text not null default '',
 approval_id uuid, pdf_ready boolean not null default false, pdf_path text unique,
 unique(parent_user_id,book_id,chapter_id)
);
create table cq_private.approvals (
 approval_id uuid primary key default gen_random_uuid(), parent_user_id uuid not null references public.cq_v4_profiles(user_id),
 request_key uuid not null, chapter_uuid uuid not null references public.cq_v4_chapters(chapter_uuid),
 payload jsonb not null, created_at timestamptz not null default now(), unique(parent_user_id,request_key)
);
alter table public.cq_v4_chapters add foreign key(approval_id) references cq_private.approvals(approval_id);
create table public.cq_v4_assignments (
 chapter_uuid uuid not null references public.cq_v4_chapters(chapter_uuid),
 child_user_id uuid not null references public.cq_v4_profiles(user_id),
 primary key(chapter_uuid,child_user_id)
);
create table cq_private.submissions (
 child_user_id uuid not null references public.cq_v4_profiles(user_id), chapter_uuid uuid not null references public.cq_v4_chapters(chapter_uuid),
 answers jsonb not null, submitted_at timestamptz not null default now(), feedback text not null default '',
 feedback_released boolean not null default false, primary key(child_user_id,chapter_uuid)
);
create table public.cq_v4_snapshots (
 owner_id uuid primary key references public.cq_v4_profiles(user_id), payload jsonb not null, updated_at timestamptz not null default now()
);
create function cq_private.require_role(expected text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); begin
 if u is null or not exists(select 1 from public.cq_v4_profiles where user_id=u and role=expected) then
 raise exception 'FORBIDDEN' using errcode='42501'; end if; return u;
end $$;
create function public.cq_v4_my_role() returns text language sql stable security definer set search_path='' as $$
 select role from public.cq_v4_profiles where user_id=auth.uid()
$$;
create function cq_private.can_read(c uuid,u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cq_v4_assignments a join public.cq_v4_chapters ch using(chapter_uuid)
 join public.cq_v4_child_access ca on ca.parent_user_id=ch.parent_user_id and ca.child_user_id=a.child_user_id
 join public.cq_v4_profiles p on p.user_id=u and p.role='student'
 where a.chapter_uuid=c and a.child_user_id=u and ca.active and ch.pdf_ready and ch.approval_id is not null)
$$;
create function public.cq_v4_issue_invite() returns text language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); token text; begin
 -- Bound issuance per parent; tokens are returned once and only hashes are stored.
 perform pg_advisory_xact_lock(hashtextextended(u::text,2));
 if (select count(*) from cq_private.invites where parent_user_id=u and created_at>now()-interval '15 minutes')>=20 then raise exception 'INVITE_RATE_LIMIT'; end if;
 token:=replace(gen_random_uuid()::text,'-','')||substr(replace(gen_random_uuid()::text,'-',''),1,16);
 insert into cq_private.invites(token_hash,parent_user_id,expires_at) values(sha256(convert_to(token,'UTF8')),u,now()+interval '15 minutes'); return token;
end $$;
create function public.cq_v4_claim_invite(p_token text,p_student_name text) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); p uuid; begin
 if p_token !~ '^[0-9a-f]{48}$' or length(trim(p_student_name)) not between 1 and 80 or p_student_name is null then raise exception 'INVALID_INVITE'; end if;
 update cq_private.invites set claimed_by=u where token_hash=sha256(convert_to(p_token,'UTF8')) and claimed_by is null and expires_at>now() returning parent_user_id into p;
 if p is null then return false; end if;
 -- A second invitation never silently reactivates a revoked student.
 insert into public.cq_v4_child_access(parent_user_id,child_user_id,student_name) values(p,u,trim(p_student_name)) on conflict do nothing; return true;
end $$;
create function public.cq_v4_approve_child(p_child_user_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); begin
 update public.cq_v4_child_access set active=true where parent_user_id=u and child_user_id=p_child_user_id; return found;
end $$;
create function public.cq_v4_revoke_child(p_child_user_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); begin
 update public.cq_v4_child_access set active=false where parent_user_id=u and child_user_id=p_child_user_id; return found;
end $$;
create function cq_private.validate_material(q jsonb,k jsonb,v jsonb) returns void language plpgsql set search_path='' as $$
declare i integer; x jsonb; begin
 if q is null or k is null or v is null or jsonb_typeof(q)<>'array' or jsonb_typeof(k)<>'array' or jsonb_typeof(v)<>'array' then raise exception 'INVALID_MATERIAL'; end if;
 if jsonb_array_length(q) not between 1 and 30 or jsonb_array_length(k)<>jsonb_array_length(q) or jsonb_array_length(v)>100 then raise exception 'INVALID_MATERIAL'; end if;
 for i in 0..jsonb_array_length(q)-1 loop
 x:=q->i;
 if coalesce(x->>'kind','') not in ('mc','inference','critical','short','comprehension') or length(trim(coalesce(x->>'text',''))) not between 1 and 2000 or (x - array['kind','text','options']) <> '{}'::jsonb then raise exception 'INVALID_QUESTION'; end if;
 if x->>'kind'='mc' then
 if jsonb_typeof(x->'options') is distinct from 'array' then raise exception 'INVALID_OPTIONS'; end if;
 if jsonb_array_length(x->'options') not between 2 and 6 or exists(select 1 from jsonb_array_elements(x->'options') o where jsonb_typeof(o)<>'string' or length(trim(o#>>'{}')) not between 1 and 500)
 or jsonb_typeof(k->i)<>'number' or (k->>i) !~ '^[0-9]+$' then raise exception 'INVALID_OPTIONS'; end if;
 if (k->>i)::integer>=jsonb_array_length(x->'options') then raise exception 'INVALID_ANSWER_KEY'; end if;
 elsif jsonb_typeof(k->i)<>'string' or length(trim(k->>i)) not between 1 and 5000 then raise exception 'INVALID_ANSWER_KEY'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(v) as words(item) where jsonb_typeof(words.item)<>'object' or length(trim(coalesce(words.item->>'word',''))) not between 1 and 200 or length(trim(coalesce(words.item->>'meaning',''))) not between 1 and 1000) then raise exception 'INVALID_VOCABULARY'; end if;
end $$;
create function public.cq_v4_register_approval_once(p_request_key uuid,p_book_id text,p_chapter_id text,p_title text,p_source text,p_questions jsonb,p_answer_key jsonb,p_vocabulary jsonb,p_writing_prompt text,p_speaking_prompt text) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); c uuid; a cq_private.approvals; body jsonb; begin
 perform cq_private.validate_material(p_questions,p_answer_key,p_vocabulary);
 if p_request_key is null or length(trim(p_book_id)) not between 1 and 200 or length(trim(p_chapter_id)) not between 1 and 200 or p_book_id is null or p_chapter_id is null or length(p_source)>45000 or length(p_writing_prompt)>5000 or length(p_speaking_prompt)>5000 then raise exception 'INVALID_MATERIAL'; end if;
 body:=jsonb_build_object('book_id',p_book_id,'chapter_id',p_chapter_id,'title',p_title,'source',p_source,'questions',p_questions,'answer_key',p_answer_key,'vocabulary',p_vocabulary,'writing_prompt',p_writing_prompt,'speaking_prompt',p_speaking_prompt);
 perform pg_advisory_xact_lock(hashtextextended(u::text||p_request_key::text,0));
 select * into a from cq_private.approvals where parent_user_id=u and request_key=p_request_key;
 if found then if a.payload<>body then raise exception 'REQUEST_KEY_REUSED'; end if; return a.approval_id; end if;
 insert into public.cq_v4_chapters(parent_user_id,book_id,chapter_id,title) values(u,p_book_id,p_chapter_id,p_title) on conflict(parent_user_id,book_id,chapter_id) do nothing;
 select chapter_uuid into c from public.cq_v4_chapters where parent_user_id=u and book_id=p_book_id and chapter_id=p_chapter_id for update;
 insert into cq_private.approvals(parent_user_id,request_key,chapter_uuid,payload) values(u,p_request_key,c,body) returning * into a; return a.approval_id;
end $$;
create function public.cq_v4_publish_approved(p_approval_id uuid,p_children uuid[]) returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); a cq_private.approvals; c public.cq_v4_chapters; child uuid; begin
 select * into a from cq_private.approvals where approval_id=p_approval_id and parent_user_id=u; if not found then raise exception 'APPROVAL_NOT_FOUND'; end if;
 select * into c from public.cq_v4_chapters where chapter_uuid=a.chapter_uuid for update;
 if not c.pdf_ready then raise exception 'PDF_NOT_READY'; end if;
 if p_children is null or cardinality(p_children) not between 1 and 100 then raise exception 'INVALID_CHILDREN'; end if;
 if c.approval_id is not null and c.approval_id<>a.approval_id then raise exception 'CHAPTER_ALREADY_PUBLISHED'; end if;
 foreach child in array p_children loop
 perform 1 from public.cq_v4_child_access where parent_user_id=u and child_user_id=child and active for update;
 if not found then raise exception 'CHILD_NOT_APPROVED'; end if;
 end loop;
 update public.cq_v4_chapters set approval_id=a.approval_id,source=a.payload->>'source',questions=a.payload->'questions',vocabulary=a.payload->'vocabulary',writing_prompt=a.payload->>'writing_prompt',speaking_prompt=a.payload->>'speaking_prompt',title=a.payload->>'title' where chapter_uuid=c.chapter_uuid;
 insert into public.cq_v4_assignments(chapter_uuid,child_user_id) select c.chapter_uuid,x from unnest(p_children) x on conflict do nothing; return c.chapter_uuid;
end $$;
create function public.cq_v4_publication_status(p_approval_id uuid,p_children uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); c public.cq_v4_chapters; missing uuid[]; begin
 select ch.* into c from public.cq_v4_chapters ch join cq_private.approvals a on a.chapter_uuid=ch.chapter_uuid where a.approval_id=p_approval_id and a.parent_user_id=u;
 if not found then raise exception 'APPROVAL_NOT_FOUND'; end if;
 select array_agg(x) into missing from unnest(p_children) x where not exists(select 1 from public.cq_v4_assignments where chapter_uuid=c.chapter_uuid and child_user_id=x);
 return jsonb_build_object('content_matches',c.approval_id=p_approval_id,'all_assigned',coalesce(cardinality(missing),0)=0,'missing_children',coalesce(to_jsonb(missing),'[]'::jsonb),'chapter_uuid',c.chapter_uuid);
end $$;
-- PDF metadata operations run with the USER JWT. Storage signing alone uses the Edge service key.
create function public.cq_v4_parent_pdf(p_action text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); c public.cq_v4_chapters; child uuid; result jsonb; begin
 if p_action='list_students' then
 select coalesce(jsonb_agg(jsonb_build_object('student_user_id',child_user_id,'student_name',student_name)),'[]') into result from public.cq_v4_child_access where parent_user_id=u and active; return jsonb_build_object('students',result);
 elsif p_action='list_chapters' then
 select coalesce(jsonb_agg(jsonb_build_object('chapter_uuid',chapter_uuid,'title',title,'pdf_ready',pdf_ready,'book_id',book_id,'chapter_id',chapter_id)),'[]') into result from public.cq_v4_chapters where parent_user_id=u; return jsonb_build_object('chapters',result);
 elsif p_action='list_assignments' then
 select coalesce(jsonb_agg(jsonb_build_object('chapter_uuid',a.chapter_uuid,'student_user_id',a.child_user_id)),'[]') into result from public.cq_v4_assignments a join public.cq_v4_chapters ch using(chapter_uuid) where ch.parent_user_id=u; return jsonb_build_object('assignments',result);
 elsif p_action='create_chapter' then
 if length(trim(coalesce(p_args->>'book_id',''))) not between 1 and 200 or length(trim(coalesce(p_args->>'chapter_id',''))) not between 1 and 200 then raise exception 'LOCAL_IDS_REQUIRED'; end if;
 insert into public.cq_v4_chapters(parent_user_id,book_id,chapter_id,title) values(u,p_args->>'book_id',p_args->>'chapter_id',p_args->>'title') on conflict(parent_user_id,book_id,chapter_id) do nothing;
 select * into c from public.cq_v4_chapters where parent_user_id=u and book_id=p_args->>'book_id' and chapter_id=p_args->>'chapter_id';
 return jsonb_build_object('chapter_uuid',c.chapter_uuid);
 end if;
 select * into c from public.cq_v4_chapters where chapter_uuid=(p_args->>'chapter_uuid')::uuid and parent_user_id=u for update;
 if not found then raise exception 'CHAPTER_NOT_FOUND'; end if;
 if p_action='upload_url' then
 if c.pdf_ready or c.approval_id is not null then raise exception 'PDF_IMMUTABLE'; end if;
 update public.cq_v4_chapters set pdf_path=u::text||'/'||c.chapter_uuid::text||'/original.pdf' where chapter_uuid=c.chapter_uuid returning * into c;
 return jsonb_build_object('bucket','cq-v4-originals','path',c.pdf_path);
 elsif p_action='inspect' then
 return jsonb_build_object('path',c.pdf_path,'pdf_ready',c.pdf_ready);
 elsif p_action='finalize_upload' then
 raise exception 'VERIFIED_EDGE_REQUIRED';
 elsif p_action in ('assign','unassign') then
 child:=(p_args->>'student_user_id')::uuid;
 perform 1 from public.cq_v4_child_access where parent_user_id=u and child_user_id=child and active for update;
 if not found then raise exception 'CHILD_NOT_APPROVED'; end if;
 if p_action='assign' then
 if not c.pdf_ready or c.approval_id is null then raise exception 'CHAPTER_NOT_PUBLISHED'; end if;
 insert into public.cq_v4_assignments values(c.chapter_uuid,child) on conflict do nothing;
 else delete from public.cq_v4_assignments where chapter_uuid=c.chapter_uuid and child_user_id=child; end if;
 return jsonb_build_object('ok',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.cq_v4_pdf_access(p_chapter_uuid uuid) returns text language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); path text; begin
 if not cq_private.can_read(p_chapter_uuid,u) then raise exception 'PDF_ACCESS_DENIED' using errcode='42501'; end if;
 select pdf_path into path from public.cq_v4_chapters where chapter_uuid=p_chapter_uuid; return path;
end $$;
create function public.cq_v4_my_chapters() returns table(chapter_uuid uuid,book_id text,chapter_id text,chapter_title text,questions jsonb) language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); begin
 return query select c.chapter_uuid,c.book_id,c.chapter_id,c.title,c.questions from public.cq_v4_chapters c where cq_private.can_read(c.chapter_uuid,u);
end $$;
create function public.cq_v4_my_chapter_activities(p_chapter_uuid uuid) returns table(vocabulary jsonb,writing_prompt text,speaking_prompt text) language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); begin
 if not cq_private.can_read(p_chapter_uuid,u) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return query select c.vocabulary,c.writing_prompt,c.speaking_prompt from public.cq_v4_chapters c where c.chapter_uuid=p_chapter_uuid;
end $$;
create function public.cq_v4_my_submission(p_chapter_uuid uuid) returns table(answers jsonb,submitted_at timestamptz,feedback text,feedback_released boolean) language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); begin
 if not cq_private.can_read(p_chapter_uuid,u) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return query select s.answers,s.submitted_at,case when s.feedback_released then s.feedback else '' end,s.feedback_released from cq_private.submissions s where s.child_user_id=u and s.chapter_uuid=p_chapter_uuid;
end $$;
-- Submission remains UI-disabled in this milestone. Server checks are provided for contract tests.
create function public.cq_v4_submit_answers(p_chapter_uuid uuid,p_answers jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('student'); c public.cq_v4_chapters; i integer; selected_answer text; begin
 select * into c from public.cq_v4_chapters where chapter_uuid=p_chapter_uuid for update;
 perform 1 from public.cq_v4_child_access where parent_user_id=c.parent_user_id and child_user_id=u and active for update;
 if not cq_private.can_read(p_chapter_uuid,u) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if exists(select 1 from cq_private.submissions where child_user_id=u and chapter_uuid=p_chapter_uuid) then raise exception 'ALREADY_SUBMITTED'; end if;
 if jsonb_typeof(p_answers) is distinct from 'object' or p_answers->'readComplete' is distinct from 'true'::jsonb or jsonb_typeof(p_answers->'answers') is distinct from 'array' then raise exception 'INVALID_ANSWERS'; end if;
 if jsonb_array_length(p_answers->'answers')<>jsonb_array_length(c.questions) or exists(select 1 from jsonb_array_elements(p_answers->'answers') a where jsonb_typeof(a)<>'string' or length(trim(a#>>'{}')) not between 1 and 10000) or length(trim(coalesce(p_answers->>'essay',''))) not between 1 and 20000 or length(trim(coalesce(p_answers->>'speaking',''))) not between 1 and 10000 then raise exception 'INVALID_ANSWERS'; end if;
 if jsonb_typeof(p_answers->'essay') is distinct from 'string' or jsonb_typeof(p_answers->'speaking') is distinct from 'string' then raise exception 'INVALID_ANSWERS'; end if;
 for i in 0..jsonb_array_length(c.questions)-1 loop
 if c.questions->i->>'kind'='mc' then
 selected_answer:=p_answers->'answers'->>i;
 if selected_answer !~ '^[0-9]{1,2}$' then raise exception 'INVALID_ANSWERS'; end if;
 if selected_answer::integer>=jsonb_array_length(c.questions->i->'options') then raise exception 'INVALID_ANSWERS'; end if;
 end if;
 end loop;
 if not exists(select 1 from storage.objects where bucket_id='cq-v4-speaking' and name in (u::text||'/'||p_chapter_uuid::text||'.webm',u::text||'/'||p_chapter_uuid::text||'.mp4',u::text||'/'||p_chapter_uuid::text||'.ogg') and (metadata->>'size')::bigint between 1 and 10485760 and metadata->>'mimetype' in ('audio/webm','audio/mp4','audio/ogg')) then raise exception 'AUDIO_REQUIRED'; end if;
 insert into cq_private.submissions(child_user_id,chapter_uuid,answers) values(u,p_chapter_uuid,p_answers-'hasAudio'); return true;
end $$;
create function public.cq_v4_parent_submissions() returns table(child_user_id uuid,student_name text,chapter_uuid uuid,chapter_title text,answers jsonb,submitted_at timestamptz,feedback text,feedback_released boolean) language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); begin
 return query select s.child_user_id,a.student_name,s.chapter_uuid,c.title,s.answers,s.submitted_at,s.feedback,s.feedback_released from cq_private.submissions s join public.cq_v4_chapters c using(chapter_uuid) join public.cq_v4_child_access a on a.child_user_id=s.child_user_id and a.parent_user_id=u where c.parent_user_id=u;
end $$;
create function public.cq_v4_release_feedback(p_child_user_id uuid,p_chapter_uuid uuid,p_feedback text,p_release boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); begin
 if p_feedback is null or length(p_feedback)>10000 or p_release and trim(p_feedback)='' then raise exception 'INVALID_FEEDBACK'; end if;
 update cq_private.submissions s set feedback=p_feedback,feedback_released=p_release from public.cq_v4_chapters c where c.chapter_uuid=s.chapter_uuid and c.parent_user_id=u and s.chapter_uuid=p_chapter_uuid and s.child_user_id=p_child_user_id;
 if not found then raise exception 'SUBMISSION_NOT_FOUND'; end if; return true;
end $$;
-- All application tables are closed by default. Only the required snapshot/access paths expose direct REST.
alter table public.cq_v4_profiles enable row level security;
alter table public.cq_v4_child_access enable row level security;
alter table public.cq_v4_chapters enable row level security;
alter table public.cq_v4_assignments enable row level security;
alter table public.cq_v4_snapshots enable row level security;
revoke all on public.cq_v4_profiles,public.cq_v4_child_access,public.cq_v4_chapters,public.cq_v4_assignments,public.cq_v4_snapshots from anon,authenticated;
grant select on public.cq_v4_child_access to authenticated;
create policy cq_parent_access on public.cq_v4_child_access for select to authenticated using(parent_user_id=auth.uid());
grant select,insert,update on public.cq_v4_snapshots to authenticated;
create policy cq_parent_snapshot on public.cq_v4_snapshots to authenticated using(owner_id=auth.uid() and public.cq_v4_my_role()='parent') with check(owner_id=auth.uid() and public.cq_v4_my_role()='parent');
-- Revoke PostgreSQL's default PUBLIC execute, including private helpers; PostgREST sees only public RPCs.
revoke all on all functions in schema cq_private from public,anon,authenticated;
do $$ declare f record; begin for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'cq_v4_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop; end $$;
commit;
