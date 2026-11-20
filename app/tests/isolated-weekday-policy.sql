-- Isolated PostgreSQL only. Pure date function, no production data.
\set ON_ERROR_STOP on
BEGIN;
DO $$
BEGIN
 IF public.cq_v4_next_weekday_date(DATE '2026-11-22',ARRAY[1,3,4],false) <> DATE '2026-11-23'
 THEN RAISE EXCEPTION 'Seowoo first Monday'; END IF;
 IF public.cq_v4_next_weekday_date(DATE '2026-11-23',ARRAY[1,3,4],false) <> DATE '2026-11-25'
 THEN RAISE EXCEPTION 'Seowoo next Wednesday'; END IF;
 IF public.cq_v4_next_weekday_date(DATE '2026-11-23',ARRAY[2,3,5],false) <> DATE '2026-11-24'
 THEN RAISE EXCEPTION 'Seojin first Tuesday'; END IF;
 IF public.cq_v4_next_weekday_date(DATE '2026-11-24',ARRAY[2,3,5],false) <> DATE '2026-11-25'
 THEN RAISE EXCEPTION 'Seojin next Wednesday'; END IF;
 IF public.cq_v4_next_weekday_date(DATE '2026-11-25',ARRAY[1,2,3,4,5],false) <> DATE '2026-11-26'
 THEN RAISE EXCEPTION 'Siwoo flexible weekdays'; END IF;
 IF public.cq_v4_next_weekday_date(DATE '2026-11-23',ARRAY[1,3,4],true) <> DATE '2026-11-23'
 THEN RAISE EXCEPTION 'Include today'; END IF;
 BEGIN
   PERFORM public.cq_v4_next_weekday_date(DATE '2026-11-23',ARRAY[]::integer[],false);
   RAISE EXCEPTION 'Empty weekdays were accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
END $$;
ROLLBACK;
\echo 'WEEKDAY_POLICY_ASSERTIONS_PASSED'
