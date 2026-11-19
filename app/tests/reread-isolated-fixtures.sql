\set ON_ERROR_STOP on
CREATE ROLE authenticated NOLOGIN; CREATE ROLE anon NOLOGIN;
GRANT authenticated TO postgres; GRANT anon TO postgres;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL);
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid,PRIMARY KEY(parent_user_id,student_user_id));
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid,PRIMARY KEY(chapter_id,student_user_id));
CREATE TABLE public.cq_v4_approval_requests(id uuid PRIMARY KEY,chapter_uuid uuid,content_hash text,questions jsonb,answer_key jsonb);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid PRIMARY KEY,approval_id uuid,approval_hash text,published_at timestamptz);
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid,child_user_id uuid,answers jsonb,submitted_at timestamptz DEFAULT now(),feedback_released boolean DEFAULT false,PRIMARY KEY(chapter_uuid,child_user_id));
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000001');
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000012');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000012'),
 ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000011');
INSERT INTO public.cq_v4_approval_requests VALUES
 ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000101','hash-a','[{"kind":"mc","options":["A","B"]},{"kind":"mc","options":["A","B"]},{"kind":"mc","options":["A","B"]}]','[0,0,0]'),
 ('00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000102','hash-b','[{"kind":"mc","options":["A","B"]}]','[0]'),
 ('00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000103','hash-c','[{"kind":"mc","options":["A","B"]}]','[0]'),
 ('00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000104','hash-d','[{"kind":"mc","options":["A","B"]}]','[null]');
INSERT INTO public.cq_v4_activities VALUES
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000201','hash-a',now()),
 ('00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000202','hash-b',now()),
 ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000203','hash-c',now()),
 ('00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000204','hash-d',now()),
 ('00000000-0000-0000-0000-000000000105',null,null,now());
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,feedback_released) VALUES
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000011','{"answers":["0","1","1"]}',true),
 ('00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000012','{"answers":["0"]}',true),
 ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000011','{"answers":[]}',true),
 ('00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000011','{"answers":["0"]}',true),
 ('00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000011','{"answers":["1"]}',true);

-- Exactly 70% (7/10) must NOT trigger a reread notice.
INSERT INTO public.cq_v4_pdf_chapters VALUES ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000001');
INSERT INTO public.cq_v4_pdf_assignments VALUES ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000011');
INSERT INTO public.cq_v4_approval_requests
SELECT '00000000-0000-0000-0000-000000000206','00000000-0000-0000-0000-000000000106','hash-70',
 (SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('A','B'))) FROM generate_series(1,10)),
 (SELECT jsonb_agg(0) FROM generate_series(1,10));
INSERT INTO public.cq_v4_activities VALUES ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000206','hash-70',now());
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,feedback_released)
VALUES ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000011',
 jsonb_build_object('answers',(SELECT jsonb_agg(CASE WHEN n<=7 THEN '0' ELSE '1' END ORDER BY n) FROM generate_series(1,10) AS n)),true);
