\set ON_ERROR_STOP on
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('cq.test_uid',true),'')::uuid $$;
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL,pdf_ready boolean,pdf_verified_at timestamptz,storage_path text,title text);
CREATE TABLE public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid NOT NULL,chapter_uuid uuid REFERENCES public.cq_v4_pdf_chapters(chapter_id),request_key uuid,book_local_id text,chapter_local_id text,title text,source_text text,questions jsonb,answer_key jsonb,vocabulary jsonb,writing_prompt text,speaking_prompt text,content_hash text);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid PRIMARY KEY REFERENCES public.cq_v4_pdf_chapters(chapter_id),questions jsonb,vocabulary jsonb,writing_prompt text,speaking_prompt text,published_at timestamptz,approval_id uuid REFERENCES public.cq_v4_approval_requests(id),approval_hash text);
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid REFERENCES public.cq_v4_pdf_chapters(chapter_id),child_user_id uuid,PRIMARY KEY(chapter_uuid,child_user_id));
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid REFERENCES public.cq_v4_pdf_chapters(chapter_id),student_user_id uuid,PRIMARY KEY(chapter_id,student_user_id));
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid()='11111111-1111-1111-1111-111111111111'::uuid $$;
INSERT INTO public.cq_v4_pdf_chapters VALUES('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',true,now(),'original.pdf','Chapter 2 : Leaving Again');
INSERT INTO public.cq_v4_pdf_assignments VALUES('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','33333333-3333-3333-3333-333333333333'),('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','44444444-4444-4444-4444-444444444444');
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,content_hash)
VALUES('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','99999999-9999-9999-9999-999999999999','b2','c2','Chapter 2','old source','[{"kind":"mc","options":["A","B"]}]','[0]','[]','write','speak','old-hash');
INSERT INTO public.cq_v4_activities VALUES('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','[{"kind":"mc","options":["A","B"]}]','[]','write','speak',now(),'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','old-hash');
CREATE TEMP TABLE payload AS SELECT 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid id,'11111111-1111-1111-1111-111111111111'::uuid parent_user_id,
'88888888-8888-8888-8888-888888888888'::uuid request_key,
'b2'::text book_local_id,'c2'::text chapter_local_id,'Chapter 2'::text title,'new source'::text source_text,
'[{"kind":"mc","text":"Q","options":["A","B"]},{"kind":"short","text":"Why?","sample":"Because."}]'::jsonb questions,
'[1,null]'::jsonb answer_key,'[]'::jsonb vocabulary,'write new'::text writing_prompt,'speak new'::text speaking_prompt;
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,content_hash)
SELECT id,parent_user_id,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,
md5(jsonb_build_array(book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt)::text)
FROM payload;
DROP TABLE payload;
\ir ../sql/development-replace-published-activity-not-for-production.sql
SELECT set_config('cq.test_uid','11111111-1111-1111-1111-111111111111',false);
DO $$
DECLARE v_id uuid:='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; v_old uuid:='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; v_new uuid:='cccccccc-cccc-cccc-cccc-cccccccccccc'; v_err text;
BEGIN
 -- Invalid old hash: no writes.
 BEGIN PERFORM public.cq_v4_replace_published_activity(v_id,v_old,'wrong',v_new);
 RAISE EXCEPTION 'wrong hash unexpectedly succeeded';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 IF (SELECT approval_id FROM public.cq_v4_activities WHERE chapter_uuid=v_id)<>v_old THEN RAISE EXCEPTION 'bad hash modified activity'; END IF;
 -- Wrong parent.
 PERFORM set_config('cq.test_uid','22222222-2222-2222-2222-222222222222',true);
 BEGIN PERFORM public.cq_v4_replace_published_activity(v_id,v_old,'old-hash',v_new);
 RAISE EXCEPTION 'wrong parent unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('cq.test_uid','11111111-1111-1111-1111-111111111111',true);
 -- Invalid answer key rolls back.
 UPDATE public.cq_v4_approval_requests SET answer_key='[3,null]' WHERE id=v_new;
 BEGIN PERFORM public.cq_v4_replace_published_activity(v_id,v_old,'old-hash',v_new);
 RAISE EXCEPTION 'bad key unexpectedly succeeded';
 EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE public.cq_v4_approval_requests SET answer_key='[1,null]',
 content_hash=md5(jsonb_build_array(book_local_id,chapter_local_id,title,source_text,questions,'[1,null]'::jsonb,vocabulary,writing_prompt,speaking_prompt)::text) WHERE id=v_new;
 -- Existing submission blocks replacement.
 INSERT INTO public.cq_v4_student_submissions VALUES(v_id,'33333333-3333-3333-3333-333333333333');
 BEGIN PERFORM public.cq_v4_replace_published_activity(v_id,v_old,'old-hash',v_new);
 RAISE EXCEPTION 'submitted chapter unexpectedly replaced';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 DELETE FROM public.cq_v4_student_submissions WHERE chapter_uuid=v_id;
 -- Valid replacement.
 IF public.cq_v4_replace_published_activity(v_id,v_old,'old-hash',v_new)<>v_id THEN RAISE EXCEPTION 'wrong return id'; END IF;
 IF (SELECT approval_id FROM public.cq_v4_activities WHERE chapter_uuid=v_id)<>v_new THEN RAISE EXCEPTION 'new approval not published'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_pdf_assignments WHERE chapter_id=v_id)<>2 THEN RAISE EXCEPTION 'assignments changed'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_approval_requests WHERE chapter_uuid=v_id)<>2 THEN RAISE EXCEPTION 'approval history not preserved'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_activities WHERE chapter_uuid=v_id)<>1 THEN RAISE EXCEPTION 'duplicate activity'; END IF;
 IF (SELECT storage_path FROM public.cq_v4_pdf_chapters WHERE chapter_id=v_id)<>'original.pdf' THEN RAISE EXCEPTION 'pdf changed'; END IF;
 -- Replay fails.
 BEGIN PERFORM public.cq_v4_replace_published_activity(v_id,v_old,'old-hash',v_new);
 RAISE EXCEPTION 'replay unexpectedly succeeded';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 RAISE NOTICE 'CHAPTER2_POSTGRES_REPLACEMENT_ASSERTIONS_PASSED';
END $$;
