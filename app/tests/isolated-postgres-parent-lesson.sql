\set ON_ERROR_STOP on
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('cq.test_uid',true),'')::uuid $$;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid()='11111111-1111-1111-1111-111111111111'::uuid $$;
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL);
CREATE TABLE public.cq_v4_approval_requests(id uuid PRIMARY KEY,chapter_uuid uuid,parent_user_id uuid,content_hash text,questions jsonb,answer_key jsonb);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid PRIMARY KEY,approval_id uuid,approval_hash text,questions jsonb,published_at timestamptz);
INSERT INTO public.cq_v4_pdf_chapters VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222');
INSERT INTO public.cq_v4_approval_requests VALUES
('cccccccc-cccc-cccc-cccc-cccccccccccc','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','verified',
'[{"kind":"mc","text":"Q1","options":["No","Yes"]},{"kind":"mc","text":"Q2","options":["No","Yes"]},{"kind":"short","text":"Why?"}]'::jsonb,
'[1,1,"Because."]'::jsonb),
('dddddddd-dddd-dddd-dddd-dddddddddddd','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222','other',
'[{"kind":"mc","text":"Secret","options":["No","Yes"]}]'::jsonb,'[1]'::jsonb);
INSERT INTO public.cq_v4_activities VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','cccccccc-cccc-cccc-cccc-cccccccccccc','verified',
'[{"kind":"mc","text":"Q1","options":["No","Yes"]},{"kind":"mc","text":"Q2","options":["No","Yes"]},{"kind":"short","text":"Why?"}]'::jsonb,now()),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-dddd-dddd-dddddddddddd','other',
'[{"kind":"mc","text":"Secret","options":["No","Yes"]}]'::jsonb,now());
\ir ../sql/development-parent-lesson-context-not-for-production.sql
SELECT set_config('cq.test_uid','11111111-1111-1111-1111-111111111111',false);
DO $$
DECLARE v_ch uuid:='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_parent_lesson(v_ch))<>1 THEN RAISE EXCEPTION 'owner cannot retrieve valid lesson'; END IF;
 IF (SELECT answer_key FROM public.cq_v4_parent_lesson(v_ch))<>'[1,1,"Because."]'::jsonb THEN RAISE EXCEPTION 'answer key mismatch'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_parent_lesson('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'))<>0 THEN RAISE EXCEPTION 'other parent lesson exposed'; END IF;
 UPDATE public.cq_v4_activities SET questions=questions||'[{"kind":"mc","text":"Unapproved","options":["A","B"]}]'::jsonb WHERE chapter_uuid=v_ch;
 IF (SELECT count(*) FROM public.cq_v4_parent_lesson(v_ch))<>0 THEN RAISE EXCEPTION 'unapproved question mismatch exposed'; END IF;
 UPDATE public.cq_v4_activities SET questions=(SELECT questions FROM public.cq_v4_approval_requests WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc'),approval_hash='wrong' WHERE chapter_uuid=v_ch;
 IF (SELECT count(*) FROM public.cq_v4_parent_lesson(v_ch))<>0 THEN RAISE EXCEPTION 'hash mismatch exposed'; END IF;
 UPDATE public.cq_v4_activities SET approval_hash='verified' WHERE chapter_uuid=v_ch;
 PERFORM set_config('cq.test_uid','22222222-2222-2222-2222-222222222222',true);
 IF (SELECT count(*) FROM public.cq_v4_parent_lesson(v_ch))<>0 THEN RAISE EXCEPTION 'nonadmin exposed'; END IF;
 RAISE NOTICE 'REREAD_PARENT_LESSON_POSTGRES_ASSERTIONS_PASSED';
END $$;
