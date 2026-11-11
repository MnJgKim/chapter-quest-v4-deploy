-- Candidate only. Never apply to production without explicit approval.
CREATE TABLE public.cq_v4_pdf_page_ranges (
 derived_pdf_uuid uuid PRIMARY KEY REFERENCES public.cq_v4_pdf_chapters(chapter_id),
 parent_user_id uuid NOT NULL REFERENCES auth.users(id),
 source_pdf_uuid uuid NOT NULL REFERENCES public.cq_v4_pdf_chapters(chapter_id),
 request_key uuid NOT NULL,
 page_start integer NOT NULL CHECK(page_start>=1),
 page_end integer NOT NULL CHECK(page_end>=page_start),
 source_page_count integer NOT NULL CHECK(source_page_count>=page_end),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
 derived_sha256 text NOT NULL CHECK(derived_sha256 ~ '^[0-9a-f]{64}$'),
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(parent_user_id,request_key),
 CHECK(derived_pdf_uuid<>source_pdf_uuid)
);
CREATE INDEX cq_v4_pdf_page_ranges_source_idx ON public.cq_v4_pdf_page_ranges(source_pdf_uuid);
ALTER TABLE public.cq_v4_pdf_page_ranges ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_pdf_page_ranges FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.cq_v4_pdf_page_ranges TO service_role;

CREATE FUNCTION public.cq_v4_commit_pdf_range(p_parent uuid,p_request uuid,p_source uuid,p_derived uuid,p_start integer,p_end integer,p_total integer,p_title text,p_source_sha text,p_derived_sha text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE prior public.cq_v4_pdf_page_ranges%ROWTYPE;
BEGIN
 IF p_parent IS NULL OR p_request IS NULL OR p_source IS NULL OR p_derived IS NULL OR p_source=p_derived
 OR p_start IS NULL OR p_end IS NULL OR p_total IS NULL OR p_start<1 OR p_end<p_start OR p_total<p_end
 OR p_title IS NULL OR length(p_title) NOT BETWEEN 1 AND 200 OR p_source_sha IS NULL OR p_derived_sha IS NULL
 OR p_source_sha !~ '^[0-9a-f]{64}$' OR p_derived_sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid PDF range' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.cq_admins a WHERE a.user_id=p_parent)
 OR NOT EXISTS(SELECT 1 FROM public.cq_v4_pdf_chapters c WHERE c.chapter_id=p_source AND c.parent_user_id=p_parent AND c.pdf_ready IS TRUE AND c.pdf_verified_at IS NOT NULL AND c.storage_path=p_parent::text||'/'||p_source::text||'.pdf')
 THEN RAISE EXCEPTION 'Owned verified source required' USING ERRCODE='42501'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_parent::text||p_request::text,0));
 SELECT * INTO prior FROM public.cq_v4_pdf_page_ranges r WHERE r.parent_user_id=p_parent AND r.request_key=p_request;
 IF FOUND THEN
  IF prior.source_pdf_uuid<>p_source OR prior.page_start<>p_start OR prior.page_end<>p_end OR prior.source_page_count<>p_total OR prior.source_sha256<>p_source_sha OR prior.title<>p_title THEN RAISE EXCEPTION 'Range request key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.derived_pdf_uuid;
 END IF;
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at)
 VALUES(p_derived,p_parent,p_title,p_parent::text||'/'||p_derived::text||'.pdf',true,now());
 INSERT INTO public.cq_v4_pdf_page_ranges(derived_pdf_uuid,parent_user_id,source_pdf_uuid,request_key,page_start,page_end,source_page_count,source_sha256,derived_sha256,title)
 VALUES(p_derived,p_parent,p_source,p_request,p_start,p_end,p_total,p_source_sha,p_derived_sha,p_title);
 RETURN p_derived;
END;
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_commit_pdf_range(uuid,uuid,uuid,uuid,integer,integer,integer,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cq_v4_commit_pdf_range(uuid,uuid,uuid,uuid,integer,integer,integer,text,text,text) TO service_role;

CREATE FUNCTION public.cq_v4_register_range_approval_once(p_request_key uuid,p_book_id text,p_chapter_id text,p_title text,p_source text,p_questions jsonb,p_answer_key jsonb,p_vocabulary jsonb,p_writing_prompt text,p_speaking_prompt text,p_source_pdf_uuid uuid,p_derived_pdf_uuid uuid,p_page_start integer,p_page_end integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_uid uuid:=auth.uid(); v_id uuid;
BEGIN
 IF v_uid IS NULL OR NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.cq_v4_pdf_page_ranges r JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=r.derived_pdf_uuid
 WHERE r.parent_user_id=v_uid AND c.parent_user_id=v_uid AND c.pdf_ready IS TRUE
 AND r.derived_pdf_uuid=p_derived_pdf_uuid AND r.source_pdf_uuid=p_source_pdf_uuid AND r.page_start=p_page_start AND r.page_end=p_page_end)
 THEN RAISE EXCEPTION 'Server verified derived PDF and exact range required' USING ERRCODE='42501'; END IF;
 v_id:=public.cq_v4_register_approval_once(p_request_key,p_book_id,p_chapter_id,p_title,p_source,p_questions,p_answer_key,p_vocabulary,p_writing_prompt,p_speaking_prompt);
 PERFORM public.cq_v4_bind_verified_pdf(v_id,p_derived_pdf_uuid);
 RETURN v_id;
END;
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_register_range_approval_once(uuid,text,text,text,text,jsonb,jsonb,jsonb,text,text,uuid,uuid,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cq_v4_register_range_approval_once(uuid,text,text,text,text,jsonb,jsonb,jsonb,text,text,uuid,uuid,integer,integer) TO authenticated;
