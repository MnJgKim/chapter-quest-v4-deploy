-- Run after recurring-publication.ISOLATED-TEST.sql on an isolated database.
\set ON_ERROR_STOP on
\set parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set student '10000000-0000-4000-8000-000000000081'
\set old '30000000-0000-4000-8000-000000000001'
\set pending '30000000-0000-4000-8000-000000000002'

INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title,pdf_verified_at,storage_path)
VALUES (:'old',:'parent',true,'Existing',now(),'original.pdf'),
       (:'pending',:'parent',true,'Pending',now(),'pending.pdf');
INSERT INTO public.cq_v4_pdf_assignments VALUES (:'old',:'student');
INSERT INTO public.cq_v4_approval_requests
VALUES (:'old',:'parent',:'old','book','Original source','original-hash','[{"kind":"short","text":"Existing question"}]',
        '["Saved answer"]','[{"word":"a","meaning":"b"}]','Write','Speak');
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions,approval_id,approval_hash)
VALUES (:'old',now(),'[{"kind":"short","text":"Existing question"}]',:'old','original-hash');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at)
VALUES (:'parent',:'student',:'old',(now() AT TIME ZONE 'Asia/Seoul')::date-1,now()-interval '1 day');
INSERT INTO public.cq_v4_student_submissions VALUES
 (:'old',:'student','{"immutable":true}',now()-interval '1 day');
INSERT INTO storage.objects(bucket_id,name) VALUES ('cq-v4-speaking',:'student'||'/'||:'old'||'.webm');
INSERT INTO public.cq_v4_approval_requests
VALUES (:'pending',:'parent',:'pending','book','Source','hash','[{"kind":"short","text":"Question"}]',
        '["Answer"]','[{"word":"a","meaning":"b"}]','Write','Speak');
CREATE TEMP TABLE old_lesson_before AS
SELECT to_jsonb(s) AS row FROM public.cq_v4_lesson_schedule s WHERE s.chapter_id=:'old';
SET ROLE authenticated;
SET "request.jwt.claim.sub" TO :'parent';
SELECT public.cq_v4_parent_enqueue_published(:'old',ARRAY[:'student']::uuid[],1,'Existing book');
SELECT public.cq_v4_parent_enqueue_published(:'old',ARRAY[:'student']::uuid[],1,'Existing book');
SELECT public.cq_v4_parent_enqueue_approved(:'pending',ARRAY[:'student']::uuid[],2);
RESET ROLE;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_approved_chapter_queue WHERE book_id='book')<>2
 OR EXISTS (
   SELECT row FROM old_lesson_before EXCEPT
   SELECT to_jsonb(s) FROM public.cq_v4_lesson_schedule s
   WHERE s.chapter_id='30000000-0000-4000-8000-000000000001'
 ) THEN RAISE EXCEPTION 'Linking an existing publication changed its lesson or duplicated the queue'; END IF;
END $$;
\if :{?require_cron}
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM cron.job
                WHERE jobname='cq-v4-recurring-release-seoul' AND schedule='0 15 * * *' AND active)
 THEN RAISE EXCEPTION 'Seoul midnight job missing'; END IF;
END $$;
\endif
CREATE TEMP VIEW current_student_data AS
 SELECT 'schedule' AS kind, to_jsonb(s) AS row FROM public.cq_v4_lesson_schedule s
 UNION ALL SELECT 'assignments', to_jsonb(a) FROM public.cq_v4_pdf_assignments a
 UNION ALL SELECT 'submissions', to_jsonb(s) FROM public.cq_v4_student_submissions s
 UNION ALL SELECT 'activity', to_jsonb(a) FROM public.cq_v4_activities a
 UNION ALL SELECT 'pdf', to_jsonb(p) FROM public.cq_v4_pdf_chapters p
 UNION ALL SELECT 'recording', to_jsonb(o) FROM storage.objects o
 UNION ALL SELECT 'approval', to_jsonb(r) FROM public.cq_v4_approval_requests r
 UNION ALL SELECT 'queue', to_jsonb(q) FROM public.cq_v4_approved_chapter_queue q;
CREATE TEMP TABLE before_pause AS SELECT * FROM current_student_data;
\ir ../../app/sql/recurring-publication-pause.REVIEW-ONLY.sql
\ir ../../app/sql/recurring-publication-pause.REVIEW-ONLY.sql
DO $$
BEGIN
 IF public.cq_v4_run_recurring_releases()<>0 OR EXISTS (
   SELECT 1 FROM public.cq_v4_student_weekday_policy WHERE enabled
 ) THEN RAISE EXCEPTION 'Recurring release remains enabled'; END IF;
 IF to_regclass('cron.job') IS NOT NULL THEN
   IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='cq-v4-recurring-release-seoul') THEN
     RAISE EXCEPTION 'The recurring job remains registered';
   END IF;
 END IF;
 IF EXISTS (SELECT * FROM current_student_data EXCEPT ALL SELECT * FROM before_pause)
 OR EXISTS (SELECT * FROM before_pause EXCEPT ALL SELECT * FROM current_student_data)
 THEN RAISE EXCEPTION 'Pause changed student data'; END IF;
END $$;
SET ROLE authenticated;
SET "request.jwt.claim.sub" TO :'student';
DO $$
BEGIN
 IF public.cq_v4_ensure_today_approved_lesson() IS NOT NULL THEN
   RAISE EXCEPTION 'Student request can still create a release';
 END IF;
 IF NOT public.cq_v4_is_released('30000000-0000-4000-8000-000000000001',auth.uid()) THEN
   RAISE EXCEPTION 'Existing released chapter was blocked';
 END IF;
END $$;
RESET ROLE;
\echo RECURRING_PAUSE_PRESERVES_STUDENT_DATA_PASSED
