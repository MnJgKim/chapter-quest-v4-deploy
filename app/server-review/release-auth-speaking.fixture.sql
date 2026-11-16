-- TEST ONLY. Snapshot of the two speaking Storage policies from the checked-in live_schema.json fixture.
-- Apply after release-auth-baseline.fixture.sql; do not run against hosted Supabase.
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cq_v4_speaking_insert_assigned_v1" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'cq-v4-speaking'::text) AND (name ~ (('^'::text || (( SELECT auth.uid() AS uid))::text) || '/[0-9a-f-]{36}\.(webm|mp4|ogg)$'::text)) AND (EXISTS ( SELECT 1
   FROM ((cq_v4_pdf_chapters c
     JOIN cq_v4_pdf_assignments a ON ((a.chapter_id = c.chapter_id)))
     JOIN cq_v4_pdf_enrollments e ON (((e.parent_user_id = c.parent_user_id) AND (e.student_user_id = a.student_user_id))))
  WHERE ((a.student_user_id = ( SELECT auth.uid() AS uid)) AND (c.pdf_ready IS TRUE) AND (((objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.webm'::text)) OR (objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.mp4'::text))) OR (objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.ogg'::text))))))));
CREATE POLICY "cq_v4_speaking_read_assigned_v1" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'cq-v4-speaking'::text) AND (EXISTS ( SELECT 1
   FROM ((cq_v4_pdf_chapters c
     JOIN cq_v4_pdf_assignments a ON ((a.chapter_id = c.chapter_id)))
     JOIN cq_v4_pdf_enrollments e ON (((e.parent_user_id = c.parent_user_id) AND (e.student_user_id = a.student_user_id))))
  WHERE ((((objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.webm'::text)) OR (objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.mp4'::text))) OR (objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.ogg'::text))) AND ((a.student_user_id = ( SELECT auth.uid() AS uid)) OR (c.parent_user_id = ( SELECT auth.uid() AS uid))))))));
