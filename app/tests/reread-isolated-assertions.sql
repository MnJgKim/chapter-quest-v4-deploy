\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $$
DECLARE n integer;v uuid;
BEGIN
 SELECT count(*) INTO n FROM public.cq_v4_parent_reread_inbox();
 IF n<>1 THEN RAISE EXCEPTION 'Parent A expected 1 reread, got %',n; END IF;
 SELECT notice_id INTO v FROM public.cq_v4_parent_reread_inbox();
 IF NOT public.cq_v4_parent_ack_reread_notice(v) THEN RAISE EXCEPTION 'Ack failed'; END IF;
 IF NOT public.cq_v4_parent_ack_reread_notice(v) THEN RAISE EXCEPTION 'Repeat ack failed'; END IF;
 SELECT count(*) INTO n FROM public.cq_v4_parent_reread_inbox() WHERE acknowledged_at IS NOT NULL;
 IF n<>1 THEN RAISE EXCEPTION 'Ack state missing'; END IF;
 SELECT count(*) INTO n FROM public.cq_v4_parent_reread_inbox() WHERE correct_mc=1 AND total_mc=3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected 1/3 objective score'; END IF;
 IF EXISTS (SELECT 1 FROM public.cq_v4_parent_reread_inbox()
            WHERE chapter_uuid IN ('00000000-0000-0000-0000-000000000106',
                                   '00000000-0000-0000-0000-000000000107'))
 THEN RAISE EXCEPTION '70 or 80 percent appeared in parent reread inbox'; END IF;
END;$$;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.cq_v4_parent_reread_inbox()) THEN RAISE EXCEPTION 'Parent cross-account leak'; END IF;
 IF public.cq_v4_parent_ack_reread_notice('00000000-0000-0000-0000-000000000101') THEN RAISE EXCEPTION 'Foreign ack accepted'; END IF;
END;$$;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
DO $$
DECLARE n integer;
BEGIN
 IF NOT public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000101') THEN RAISE EXCEPTION 'Missing student reread'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000102') THEN RAISE EXCEPTION 'Cross-student read'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000103') THEN RAISE EXCEPTION 'Unscored should not notify'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000104') THEN RAISE EXCEPTION 'Missing key should not notify'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000105') THEN RAISE EXCEPTION 'Missing approval should not notify'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000106') THEN RAISE EXCEPTION 'Exactly 70 percent incorrectly flagged'; END IF;
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000107') THEN RAISE EXCEPTION '80 percent incorrectly flagged'; END IF;
END;$$;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000012',false);
DO $$
BEGIN
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000102') THEN RAISE EXCEPTION '100 percent incorrectly flagged'; END IF;
END;$$;
RESET ROLE;
DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.cq_v4_reread_ack;
 IF n<>1 THEN RAISE EXCEPTION 'Duplicate acknowledgement rows'; END IF;
 SELECT count(*) INTO n FROM public.cq_v4_student_submissions;
 IF n<>7 THEN RAISE EXCEPTION 'Submissions unexpectedly changed'; END IF;
 IF (SELECT answers FROM public.cq_v4_student_submissions WHERE chapter_uuid='00000000-0000-0000-0000-000000000101' AND child_user_id='00000000-0000-0000-0000-000000000011') IS DISTINCT FROM '{"answers":["0","1","1"]}'::jsonb THEN RAISE EXCEPTION 'Submitted answers were modified'; END IF;
 IF (SELECT snapshot_payload FROM public.cq_v4_snapshots WHERE chapter_uuid='00000000-0000-0000-0000-000000000101') IS DISTINCT FROM '{"immutable":"original"}'::jsonb THEN RAISE EXCEPTION 'Immutable snapshot changed'; END IF;
END;$$;
-- Inspect exact scoring boundaries under the privileged fixture owner, without granting
-- authenticated users direct access to the SECURITY DEFINER scorer.
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $exact_scores$
DECLARE v_correct integer; v_total integer;
BEGIN
 SELECT correct_mc,total_mc INTO v_correct,v_total
 FROM public.cq_v4_objective_reread_score('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000011');
 IF v_correct IS DISTINCT FROM 7 OR v_total IS DISTINCT FROM 10
 THEN RAISE EXCEPTION 'Expected exact 7/10 score, got %/%',v_correct,v_total; END IF;
 SELECT correct_mc,total_mc INTO v_correct,v_total
 FROM public.cq_v4_objective_reread_score('00000000-0000-0000-0000-000000000107','00000000-0000-0000-0000-000000000011');
 IF v_correct IS DISTINCT FROM 8 OR v_total IS DISTINCT FROM 10
 THEN RAISE EXCEPTION 'Expected exact 8/10 score, got %/%',v_correct,v_total; END IF;
 IF EXISTS (SELECT 1 FROM public.cq_v4_objective_reread_score('00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000011'))
 THEN RAISE EXCEPTION 'Unapproved legacy publication was scored'; END IF;
END;$exact_scores$;
SELECT set_config('test.uid','',false);

-- Verify direct score access is denied, and anonymous access to all public RPCs is denied.
DO $access$
BEGIN
 IF has_function_privilege('authenticated','public.cq_v4_objective_reread_score(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Authenticated user can call privileged objective scorer directly'; END IF;
 IF has_function_privilege('anon','public.cq_v4_objective_reread_score(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous user can call privileged objective scorer'; END IF;
 IF has_function_privilege('anon','public.cq_v4_parent_reread_inbox()','EXECUTE')
 OR has_function_privilege('anon','public.cq_v4_parent_ack_reread_notice(uuid)','EXECUTE')
 OR has_function_privilege('anon','public.cq_v4_my_released_reread_suggestion(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous user can access reread RPC'; END IF;
 IF has_table_privilege('authenticated','public.cq_v4_reread_ack','INSERT')
 OR has_table_privilege('authenticated','public.cq_v4_reread_ack','UPDATE')
 THEN RAISE EXCEPTION 'Authenticated user can modify reread acknowledgements directly'; END IF;
END;$access$;

-- A student's unread or unreleased feedback must not disclose the score.
SET ROLE authenticated;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
RESET ROLE;
UPDATE public.cq_v4_student_submissions SET feedback_released=false
WHERE chapter_uuid='00000000-0000-0000-0000-000000000101';
SET ROLE authenticated;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
DO $tag$
BEGIN
 IF public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000101')
 THEN RAISE EXCEPTION 'Unreleased feedback leaked'; END IF;
END;$tag$;
RESET ROLE;
SET ROLE authenticated;
-- Parent notices must also remain hidden until feedback is released.
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $parent_unreleased$
BEGIN
 IF EXISTS(SELECT 1 FROM public.cq_v4_parent_reread_inbox()
           WHERE chapter_uuid='00000000-0000-0000-0000-000000000101')
 THEN RAISE EXCEPTION 'Parent inbox leaked unreleased feedback'; END IF;
END;$parent_unreleased$;
RESET ROLE;
UPDATE public.cq_v4_student_submissions SET feedback_released=true
WHERE chapter_uuid='00000000-0000-0000-0000-000000000101';
-- Releasing feedback must restore both the parent's notice and the student's suggestion.
SET ROLE authenticated;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $released_parent$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_parent_reread_inbox()
     WHERE chapter_uuid='00000000-0000-0000-0000-000000000101') <> 1
 THEN RAISE EXCEPTION 'Parent reread notice not restored after feedback release'; END IF;
END;$released_parent$;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
DO $released_student$
BEGIN
 IF NOT public.cq_v4_my_released_reread_suggestion('00000000-0000-0000-0000-000000000101')
 THEN RAISE EXCEPTION 'Student reread suggestion not restored after feedback release'; END IF;
END;$released_student$;
RESET ROLE;


SELECT 'REREAD_ISOLATED_ASSERTIONS_PASSED' AS result;
