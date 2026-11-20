-- Assertions run only against disposable PostgreSQL database.
DO $$
DECLARE p uuid:='00000000-0000-0000-0000-000000000001';
s uuid:='00000000-0000-0000-0000-000000000002';
c1 uuid:='00000000-0000-0000-0000-000000000003';
c2 uuid:='00000000-0000-0000-0000-000000000004';
v uuid;
BEGIN
 PERFORM set_config('test.uid',p::text,false);
 PERFORM set_config('test.admin','yes',false);
 INSERT INTO public.cq_v4_pdf_enrollments VALUES(p,s);
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready) VALUES(c1,p,true),(c2,p,true);
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(c1,s),(c2,s);
 INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions) VALUES
 (c1,'2026-11-01'::timestamptz,'[]'::jsonb),(c2,'2026-11-01'::timestamptz,'[]'::jsonb);
 PERFORM public.cq_v4_parent_set_weekdays(s,ARRAY[1,3,4],DATE '2026-11-23',true);
 PERFORM public.cq_v4_parent_queue_approved_chapter(s,c1,1);
 PERFORM public.cq_v4_parent_queue_approved_chapter(s,c2,2);
 PERFORM set_config('test.uid',s::text,false);
 PERFORM set_config('test.admin','no',false);
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-22 14:59:59+00'::timestamptz) IS NOT NULL
 THEN RAISE EXCEPTION 'Released before Seoul midnight'; END IF;
 v:=public.cq_v4_ensure_approved_lesson_at('2026-11-22 15:00:00+00'::timestamptz);
 IF v IS DISTINCT FROM c1 THEN RAISE EXCEPTION 'First approved chapter not released'; END IF;
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-22 15:00:01+00'::timestamptz) IS NOT NULL
 THEN RAISE EXCEPTION 'Duplicate release returned non-null'; END IF;
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-23 15:00:00+00'::timestamptz) IS NOT NULL
 THEN RAISE EXCEPTION 'Tuesday released or bypassed unfinished lesson'; END IF;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,submitted_at)
 VALUES(c1,s,'{}'::jsonb,'2026-11-23 01:00+00');
 v:=public.cq_v4_ensure_approved_lesson_at('2026-11-24 15:00:00+00'::timestamptz);
 IF v IS DISTINCT FROM c2 THEN RAISE EXCEPTION 'Next chapter not released on Wednesday'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id=s)<>2
 THEN RAISE EXCEPTION 'Duplicate or missing schedule'; END IF;
 RAISE NOTICE 'AUTO_RELEASE_ISOLATED_ASSERTIONS_PASSED';
END $$;
