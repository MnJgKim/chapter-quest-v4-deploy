-- Run on an isolated PostgreSQL database after isolated-postgres-bootstrap.sql.
\set ON_ERROR_STOP on
\set display_parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set display_student '10000000-0000-4000-8000-000000000111'
\set other '10000000-0000-4000-8000-000000000112'
\set unnamed '10000000-0000-4000-8000-000000000113'
\set chapter '20000000-0000-4000-8000-000000000111'
CREATE TABLE public.cq_v4_invites(
 invite_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), parent_user_id uuid, claimed_by uuid, student_name text,
 approved_at timestamptz, revoked_at timestamptz, claimed_at timestamptz, created_at timestamptz DEFAULT now()
);
ALTER TABLE public.cq_v4_student_submissions ADD COLUMN feedback text,
 ADD COLUMN feedback_released boolean DEFAULT false;
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 (:'display_parent',:'display_student'),(:'display_parent',:'other'),(:'display_parent',:'unnamed');
INSERT INTO public.cq_v4_invites(parent_user_id,claimed_by,student_name,approved_at,claimed_at)
VALUES (:'display_parent',:'other','기존 테스트 이름',now(),now()),
 (:'display_parent',:'unnamed','   ',now(),now());
INSERT INTO public.cq_v4_pdf_chapters VALUES (:'chapter',:'display_parent',true,'Synthetic');
INSERT INTO public.cq_v4_pdf_assignments VALUES (:'chapter',:'display_student');
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
VALUES (:'chapter',:'display_student','{"preserved":true}');

\ir ../../app/sql/student-display-names.REVIEW-ONLY.sql
\set display_previous_is_null true
\ir ../../app/sql/seowoo-display-name.REVIEW-ONLY.sql
SET ROLE authenticated;
SET "request.jwt.claim.sub" TO :'display_parent';
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_list_child_access()
     WHERE student_name IN ('서우','기존 테스트 이름','계정 00000113'))<>3 THEN
   RAISE EXCEPTION 'Parent list lost an existing name or failed to resolve the new one';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.cq_v4_parent_submissions()
                WHERE student_name='서우' AND answers='{"preserved":true}') THEN
   RAISE EXCEPTION 'Parent submissions use the wrong name or changed their content';
 END IF;
 IF has_function_privilege('public.cq_v4_enrolled_display_name(uuid,uuid)','EXECUTE') THEN
   RAISE EXCEPTION 'Private name resolver is client-callable';
 END IF;
END $$;
SET "request.jwt.claim.sub" TO :'display_student';
DO $$
BEGIN
 IF public.cq_v4_my_display_name() IS DISTINCT FROM '서우'
    OR EXISTS (SELECT 1 FROM public.cq_v4_list_child_access())
    OR EXISTS (SELECT 1 FROM public.cq_v4_parent_submissions()) THEN
   RAISE EXCEPTION 'Student name lookup or isolation failed';
 END IF;
END $$;
SET "request.jwt.claim.sub" TO :'other';
DO $$
BEGIN
 IF public.cq_v4_my_display_name() IS DISTINCT FROM '기존 테스트 이름' THEN
   RAISE EXCEPTION 'Existing test name was lost';
 END IF;
END $$;
SET "request.jwt.claim.sub" TO :'unnamed';
DO $$
BEGIN
 IF public.cq_v4_my_display_name() IS NOT NULL THEN
   RAISE EXCEPTION 'Whitespace-only name was exposed';
 END IF;
END $$;
RESET ROLE;

\set display_previous_is_null false
\ir ../../app/sql/seowoo-display-name.REVIEW-ONLY.sql
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.cq_v4_pdf_enrollments WHERE display_name IS NOT NULL)
    OR (SELECT count(*) FROM public.cq_v4_invites)<>2
    OR (SELECT count(*) FROM public.cq_v4_pdf_assignments)<>1
    OR (SELECT count(*) FROM public.cq_v4_student_submissions WHERE answers='{"preserved":true}')<>1
 THEN RAISE EXCEPTION 'Rollback changed unrelated records'; END IF;
END $$;
\echo STUDENT_DISPLAY_NAME_PARENT_STUDENT_AND_ROLLBACK_PASSED
