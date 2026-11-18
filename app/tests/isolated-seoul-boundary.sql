-- ISOLATED CI ONLY: deterministic Asia/Seoul midnight boundary assertions.
\set ON_ERROR_STOP on
DO $$
DECLARE
 before_midnight timestamptz := '2026-11-18 14:59:59+00'::timestamptz;
 at_midnight timestamptz := '2026-11-18 15:00:00+00'::timestamptz;
BEGIN
 IF (before_midnight AT TIME ZONE 'Asia/Seoul')::date <> DATE '2026-11-18'
 THEN RAISE EXCEPTION '23:59:59 must be November 18 in Seoul'; END IF;
 IF (at_midnight AT TIME ZONE 'Asia/Seoul')::date <> DATE '2026-11-19'
 THEN RAISE EXCEPTION '00:00:00 must be November 19 in Seoul'; END IF;
 IF EXTRACT(ISODOW FROM DATE '2026-11-23') <> 1
 THEN RAISE EXCEPTION 'Seowoo Monday baseline incorrect'; END IF;
 IF EXTRACT(ISODOW FROM DATE '2026-11-24') <> 2
 THEN RAISE EXCEPTION 'Seojin Tuesday baseline incorrect'; END IF;
END $$;
\echo 'SEOUL_BOUNDARY_ASSERTIONS_PASSED'
