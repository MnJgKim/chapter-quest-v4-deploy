-- REVIEW ONLY. Pure scheduling helper; never assigns, releases, or updates lessons.
-- No student IDs or production secrets are stored here.
CREATE OR REPLACE FUNCTION public.cq_v4_next_weekday_date(
 p_from date, p_weekdays integer[], p_include_today boolean DEFAULT false
) RETURNS date LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $$
DECLARE v_offset integer;
BEGIN
 IF p_from IS NULL OR p_weekdays IS NULL
    OR pg_catalog.cardinality(p_weekdays) NOT BETWEEN 1 AND 7
    OR NOT (p_weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]) THEN
   RAISE EXCEPTION 'Invalid weekday policy' USING ERRCODE='22023';
 END IF;
 FOR v_offset IN (CASE WHEN p_include_today THEN 0 ELSE 1 END)..7 LOOP
   IF EXTRACT(ISODOW FROM (p_from + v_offset)::timestamp)::integer = ANY(p_weekdays) THEN
     RETURN p_from + v_offset;
   END IF;
 END LOOP;
 RAISE EXCEPTION 'No matching weekday' USING ERRCODE='22023';
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_next_weekday_date(date,integer[],boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_next_weekday_date(date,integer[],boolean) TO authenticated;
-- Integration blocker: a parent-authorized scheduler must select the next approved,
-- unsubmitted chapter atomically, and preserve explicitly approved makeup dates.
-- Never infer chapter order from UUIDs or auto-assign a student's chapters here.
