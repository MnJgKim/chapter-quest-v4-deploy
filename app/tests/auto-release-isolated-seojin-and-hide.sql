-- Run AFTER auto-release-isolated-assertions.sql in disposable database only.
DO $$
DECLARE p uuid:='00000000-0000-0000-0000-000000000001';
 s uuid:='00000000-0000-0000-0000-000000000012';
 c1 uuid:='00000000-0000-0000-0000-000000000013';
 c2 uuid:='00000000-0000-0000-0000-000000000014';
 c3 uuid:='00000000-0000-0000-0000-000000000015';
 v uuid;
BEGIN
 PERFORM set_config('test.uid',p::text,false);
 PERFORM set_config('test.admin','yes',false);
 INSERT INTO public.cq_v4_pdf_enrollments VALUES(p,s);
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready) VALUES(c1,p,true),(c2,p,true),(c3,p,true);
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(c1,s),(c2,s),(c3,s);
 INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions)
 VALUES(c1,'2026-11-01'::timestamptz,'[]'),(c2,'2026-11-01'::timestamptz,'[]'),(c3,'2026-11-01'::timestamptz,'[]');
 PERFORM public.cq_v4_parent_set_weekdays(s,ARRAY[2,3,5],DATE '2026-11-24',true);
 PERFORM public.cq_v4_parent_queue_approved_chapter(s,c1,1);
 PERFORM public.cq_v4_parent_queue_approved_chapter(s,c2,2);
 PERFORM public.cq_v4_parent_queue_approved_chapter(s,c3,3);
 -- Parent's existing manual schedule always wins over the next queued chapter.
 INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,timezone,released_at,auto_release_paused)
 VALUES(p,s,c1,DATE '2026-11-24','Asia/Seoul',NULL,true);
 PERFORM set_config('test.uid',s::text,false);
 PERFORM set_config('test.admin','no',false);
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-23 15:00+00') IS NOT NULL
 THEN RAISE EXCEPTION 'Manual hidden lesson reopened'; END IF;
 IF (SELECT released_at IS NOT NULL FROM public.cq_v4_lesson_schedule WHERE student_user_id=s AND chapter_id=c1)
 THEN RAISE EXCEPTION 'Manual hide not preserved'; END IF;
 -- Unfinished scheduled lesson must prevent skipping to later queue entry.
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-24 15:00+00') IS NOT NULL
 THEN RAISE EXCEPTION 'Unfinished hidden lesson bypassed'; END IF;
 -- Parent explicitly releases and student submits.
 PERFORM set_config('test.uid',p::text,false);
 PERFORM set_config('test.admin','yes',false);
 PERFORM public.cq_v4_parent_set_lesson_release(s,c1,true);
 IF (SELECT auto_release_paused FROM public.cq_v4_lesson_schedule WHERE student_user_id=s AND chapter_id=c1)
 THEN RAISE EXCEPTION 'Explicit parent release remained paused'; END IF;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,submitted_at)
 VALUES(c1,s,'{}','2026-11-24 01:00+00');
 PERFORM set_config('test.uid',s::text,false);
 PERFORM set_config('test.admin','no',false);
 v:=public.cq_v4_ensure_approved_lesson_at('2026-11-24 15:00+00');
 IF v IS DISTINCT FROM c2 THEN RAISE EXCEPTION 'Wednesday next chapter failed'; END IF;
 IF public.cq_v4_ensure_approved_lesson_at('2026-11-25 15:00+00') IS NOT NULL
 THEN RAISE EXCEPTION 'Unfinished Wednesday lesson bypassed on Thursday'; END IF;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,submitted_at)
 VALUES(c2,s,'{}','2026-11-25 01:00+00');
 v:=public.cq_v4_ensure_approved_lesson_at('2026-11-26 15:00+00');
 IF v IS DISTINCT FROM c3 THEN RAISE EXCEPTION 'Friday next chapter failed'; END IF;
 IF (SELECT COUNT(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id=s)<>3
 THEN RAISE EXCEPTION 'Duplicate schedule rows'; END IF;
 RAISE NOTICE 'AUTO_RELEASE_SEOJIN_HIDE_ROLLOVER_ASSERTIONS_PASSED';
END $$;
