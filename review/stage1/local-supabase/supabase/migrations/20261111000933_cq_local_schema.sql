-- LOCAL TEST SCHEMA ONLY. Never apply this bootstrap to a hosted project.

create extension if not exists pgcrypto with schema extensions;

create table public.cq_students("id" uuid DEFAULT gen_random_uuid() NOT NULL,"name" text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_books("id" uuid DEFAULT gen_random_uuid() NOT NULL,"title" text NOT NULL,"author" text DEFAULT ''::text NOT NULL,"pdf_path" text,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_chapters("id" uuid DEFAULT gen_random_uuid() NOT NULL,"book_id" uuid NOT NULL,"title" text NOT NULL,"chapter_number" integer NOT NULL,"start_page" integer,"end_page" integer,"questions" jsonb DEFAULT '[]'::jsonb NOT NULL,"vocabulary" jsonb DEFAULT '[]'::jsonb NOT NULL,"activities" jsonb DEFAULT '{}'::jsonb NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_assignments("id" uuid DEFAULT gen_random_uuid() NOT NULL,"student_id" uuid NOT NULL,"chapter_id" uuid NOT NULL,"assigned_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_submissions("id" uuid DEFAULT gen_random_uuid() NOT NULL,"assignment_id" uuid NOT NULL,"read_completed" boolean DEFAULT false NOT NULL,"answers" jsonb DEFAULT '{}'::jsonb NOT NULL,"writing" text DEFAULT ''::text NOT NULL,"speaking_paths" jsonb DEFAULT '{}'::jsonb NOT NULL,"submitted" boolean DEFAULT false NOT NULL,"submitted_at" timestamp with time zone,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_feedback("id" uuid DEFAULT gen_random_uuid() NOT NULL,"submission_id" uuid NOT NULL,"feedback_text" text DEFAULT ''::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_student_devices("id" uuid DEFAULT gen_random_uuid() NOT NULL,"student_id" uuid NOT NULL,"auth_user_id" uuid NOT NULL,"approved_by" uuid NOT NULL,"connected_at" timestamp with time zone DEFAULT now() NOT NULL,"revoked_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_admins("user_id" uuid NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_pairing_requests("id" uuid DEFAULT gen_random_uuid() NOT NULL,"auth_user_id" uuid NOT NULL,"pairing_code" text NOT NULL,"expires_at" timestamp with time zone NOT NULL,"approved_student_id" uuid,"approved_by" uuid,"approved_at" timestamp with time zone,"used_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_pdf_enrollments("parent_user_id" uuid NOT NULL,"student_user_id" uuid NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_pdf_chapters("chapter_id" uuid DEFAULT gen_random_uuid() NOT NULL,"parent_user_id" uuid NOT NULL,"title" text NOT NULL,"storage_path" text NOT NULL,"pdf_ready" boolean DEFAULT false NOT NULL,"pdf_verified_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_pdf_assignments("chapter_id" uuid NOT NULL,"student_user_id" uuid NOT NULL,"assigned_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_snapshots("owner_id" uuid NOT NULL,"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_activities("chapter_uuid" uuid NOT NULL,"questions" jsonb DEFAULT '[]'::jsonb NOT NULL,"vocabulary" jsonb DEFAULT '[]'::jsonb NOT NULL,"writing_prompt" text DEFAULT ''::text NOT NULL,"speaking_prompt" text DEFAULT ''::text NOT NULL,"published_at" timestamp with time zone,"approval_id" uuid,"approval_hash" text);

create table public.cq_v4_student_submissions("chapter_uuid" uuid NOT NULL,"child_user_id" uuid NOT NULL,"answers" jsonb NOT NULL,"submitted_at" timestamp with time zone DEFAULT now() NOT NULL,"feedback" text,"feedback_released" boolean DEFAULT false NOT NULL);

create table public.cq_v4_approval_requests("id" uuid DEFAULT gen_random_uuid() NOT NULL,"parent_user_id" uuid NOT NULL,"request_key" uuid NOT NULL,"book_local_id" text NOT NULL,"chapter_local_id" text NOT NULL,"title" text NOT NULL,"source_text" text NOT NULL,"questions" jsonb NOT NULL,"answer_key" jsonb NOT NULL,"vocabulary" jsonb NOT NULL,"writing_prompt" text NOT NULL,"speaking_prompt" text NOT NULL,"content_hash" text NOT NULL,"chapter_uuid" uuid,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

create table public.cq_v4_invites("invite_id" uuid DEFAULT gen_random_uuid() NOT NULL,"parent_user_id" uuid NOT NULL,"token_hash" text NOT NULL,"expires_at" timestamp with time zone NOT NULL,"claimed_by" uuid,"student_name" text,"claimed_at" timestamp with time zone,"approved_at" timestamp with time zone,"revoked_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL);

alter table public."cq_v4_activities" add constraint "cq_v4_activities_pkey" PRIMARY KEY (chapter_uuid);

alter table public."cq_students" add constraint "cq_students_pkey" PRIMARY KEY (id);

alter table public."cq_books" add constraint "cq_books_pkey" PRIMARY KEY (id);

alter table public."cq_chapters" add constraint "cq_chapters_pkey" PRIMARY KEY (id);

alter table public."cq_chapters" add constraint "cq_chapters_book_id_chapter_number_key" UNIQUE (book_id, chapter_number);

alter table public."cq_assignments" add constraint "cq_assignments_pkey" PRIMARY KEY (id);

alter table public."cq_assignments" add constraint "cq_assignments_student_id_chapter_id_key" UNIQUE (student_id, chapter_id);

alter table public."cq_submissions" add constraint "cq_submissions_pkey" PRIMARY KEY (id);

alter table public."cq_submissions" add constraint "cq_submissions_assignment_id_key" UNIQUE (assignment_id);

alter table public."cq_feedback" add constraint "cq_feedback_pkey" PRIMARY KEY (id);

alter table public."cq_feedback" add constraint "cq_feedback_submission_id_key" UNIQUE (submission_id);

alter table public."cq_student_devices" add constraint "cq_student_devices_pkey" PRIMARY KEY (id);

alter table public."cq_student_devices" add constraint "cq_student_devices_auth_user_id_key" UNIQUE (auth_user_id);

alter table public."cq_admins" add constraint "cq_admins_pkey" PRIMARY KEY (user_id);

alter table public."cq_pairing_requests" add constraint "cq_pairing_requests_pkey" PRIMARY KEY (id);

alter table public."cq_pairing_requests" add constraint "cq_pairing_requests_pairing_code_key" UNIQUE (pairing_code);

alter table public."cq_v4_pdf_enrollments" add constraint "cq_v4_distinct_users" CHECK ((parent_user_id <> student_user_id));

alter table public."cq_v4_pdf_enrollments" add constraint "cq_v4_pdf_enrollments_pkey" PRIMARY KEY (parent_user_id, student_user_id);

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_pdf_chapters_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)));

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_storage_path_valid" CHECK ((storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]pdf$'::text));

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_storage_path_owner_binding" CHECK ((storage_path = ((((parent_user_id)::text || '/'::text) || (chapter_id)::text) || '.pdf'::text)));

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_pdf_chapters_pkey" PRIMARY KEY (chapter_id);

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_pdf_chapters_storage_path_key" UNIQUE (storage_path);

alter table public."cq_v4_pdf_assignments" add constraint "cq_v4_pdf_assignments_pkey" PRIMARY KEY (chapter_id, student_user_id);

alter table public."cq_v4_snapshots" add constraint "cq_v4_snapshots_pkey" PRIMARY KEY (owner_id);

alter table public."cq_v4_activities" add constraint "cq_v4_activities_questions_check" CHECK ((jsonb_typeof(questions) = 'array'::text));

alter table public."cq_v4_activities" add constraint "cq_v4_activities_vocabulary_check" CHECK ((jsonb_typeof(vocabulary) = 'array'::text));

alter table public."cq_v4_student_submissions" add constraint "cq_v4_student_submissions_answers_check" CHECK ((jsonb_typeof(answers) = 'object'::text));

alter table public."cq_v4_student_submissions" add constraint "cq_v4_student_submissions_pkey" PRIMARY KEY (chapter_uuid, child_user_id);

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)));

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_questions_check" CHECK ((jsonb_typeof(questions) = 'array'::text));

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_answer_key_check" CHECK ((jsonb_typeof(answer_key) = 'array'::text));

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_vocabulary_check" CHECK ((jsonb_typeof(vocabulary) = 'array'::text));

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_pkey" PRIMARY KEY (id);

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_parent_user_id_request_key_key" UNIQUE (parent_user_id, request_key);

alter table public."cq_v4_invites" add constraint "cq_v4_invite_claim_consistency" CHECK (((claimed_by IS NULL) = (claimed_at IS NULL)));

alter table public."cq_v4_invites" add constraint "cq_v4_invites_pkey" PRIMARY KEY (invite_id);

alter table public."cq_v4_invites" add constraint "cq_v4_invites_token_hash_key" UNIQUE (token_hash);

alter table public."cq_pairing_requests" add constraint "cq_pairing_requests_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_pairing_requests" add constraint "cq_pairing_requests_approved_student_id_fkey" FOREIGN KEY (approved_student_id) REFERENCES cq_students(id);

alter table public."cq_pairing_requests" add constraint "cq_pairing_requests_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id);

alter table public."cq_chapters" add constraint "cq_chapters_book_id_fkey" FOREIGN KEY (book_id) REFERENCES cq_books(id) ON DELETE CASCADE;

alter table public."cq_assignments" add constraint "cq_assignments_student_id_fkey" FOREIGN KEY (student_id) REFERENCES cq_students(id) ON DELETE CASCADE;

alter table public."cq_assignments" add constraint "cq_assignments_chapter_id_fkey" FOREIGN KEY (chapter_id) REFERENCES cq_chapters(id) ON DELETE CASCADE;

alter table public."cq_submissions" add constraint "cq_submissions_assignment_id_fkey" FOREIGN KEY (assignment_id) REFERENCES cq_assignments(id) ON DELETE CASCADE;

alter table public."cq_feedback" add constraint "cq_feedback_submission_id_fkey" FOREIGN KEY (submission_id) REFERENCES cq_submissions(id) ON DELETE CASCADE;

alter table public."cq_student_devices" add constraint "cq_student_devices_student_id_fkey" FOREIGN KEY (student_id) REFERENCES cq_students(id) ON DELETE CASCADE;

alter table public."cq_student_devices" add constraint "cq_student_devices_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_student_devices" add constraint "cq_student_devices_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id);

alter table public."cq_admins" add constraint "cq_admins_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_pdf_enrollments" add constraint "cq_v4_pdf_enrollments_parent_user_id_fkey" FOREIGN KEY (parent_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_pdf_enrollments" add constraint "cq_v4_pdf_enrollments_student_user_id_fkey" FOREIGN KEY (student_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_pdf_chapters" add constraint "cq_v4_pdf_chapters_parent_user_id_fkey" FOREIGN KEY (parent_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_pdf_assignments" add constraint "cq_v4_pdf_assignments_chapter_id_fkey" FOREIGN KEY (chapter_id) REFERENCES cq_v4_pdf_chapters(chapter_id) ON DELETE CASCADE;

alter table public."cq_v4_pdf_assignments" add constraint "cq_v4_pdf_assignments_student_user_id_fkey" FOREIGN KEY (student_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_snapshots" add constraint "cq_v4_snapshots_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_activities" add constraint "cq_v4_activities_chapter_uuid_fkey" FOREIGN KEY (chapter_uuid) REFERENCES cq_v4_pdf_chapters(chapter_id) ON DELETE CASCADE;

alter table public."cq_v4_student_submissions" add constraint "cq_v4_student_submissions_chapter_uuid_fkey" FOREIGN KEY (chapter_uuid) REFERENCES cq_v4_pdf_chapters(chapter_id) ON DELETE RESTRICT;

alter table public."cq_v4_student_submissions" add constraint "cq_v4_student_submissions_child_user_id_fkey" FOREIGN KEY (child_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_parent_user_id_fkey" FOREIGN KEY (parent_user_id) REFERENCES auth.users(id);

alter table public."cq_v4_approval_requests" add constraint "cq_v4_approval_requests_chapter_uuid_fkey" FOREIGN KEY (chapter_uuid) REFERENCES cq_v4_pdf_chapters(chapter_id);

alter table public."cq_v4_activities" add constraint "cq_v4_activities_approval_id_fkey" FOREIGN KEY (approval_id) REFERENCES cq_v4_approval_requests(id);

alter table public."cq_v4_invites" add constraint "cq_v4_invites_parent_user_id_fkey" FOREIGN KEY (parent_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table public."cq_v4_invites" add constraint "cq_v4_invites_claimed_by_fkey" FOREIGN KEY (claimed_by) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX cq_v4_invites_parent_idx ON public.cq_v4_invites USING btree (parent_user_id, created_at DESC);

CREATE INDEX cq_v4_pdf_assignment_student_idx ON public.cq_v4_pdf_assignments USING btree (student_user_id);

CREATE UNIQUE INDEX cq_v4_invites_one_pending_child_idx ON public.cq_v4_invites USING btree (parent_user_id, claimed_by) WHERE ((claimed_by IS NOT NULL) AND (approved_at IS NULL) AND (revoked_at IS NULL));

CREATE INDEX cq_pairing_requests_auth_idx ON public.cq_pairing_requests USING btree (auth_user_id);

CREATE INDEX cq_student_devices_student_idx ON public.cq_student_devices USING btree (student_id);

CREATE OR REPLACE FUNCTION public.cq_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.cq_admins a
    WHERE a.user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_approve_child(p_child_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_invite_id uuid;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF p_child_user_id IS NULL OR p_child_user_id=v_uid THEN RETURN false; END IF;
 -- Serialize concurrent approval and revocation for this exact parent/child pair.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || ':' || p_child_user_id::text, 927542));
 SELECT invite_id INTO v_invite_id FROM public.cq_v4_invites
 WHERE parent_user_id=v_uid AND claimed_by=p_child_user_id AND claimed_at IS NOT NULL
   AND revoked_at IS NULL AND approved_at IS NULL
 ORDER BY claimed_at DESC LIMIT 1 FOR UPDATE;
 IF v_invite_id IS NULL THEN RETURN false; END IF;
 INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id)
 VALUES(v_uid,p_child_user_id) ON CONFLICT DO NOTHING;
 UPDATE public.cq_v4_invites SET approved_at=now(),revoked_at=NULL WHERE invite_id=v_invite_id;
 RETURN true;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_bind_verified_pdf(p_approval_id uuid, p_chapter_uuid uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_existing uuid;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_chapter_uuid IS NULL THEN RAISE EXCEPTION 'Missing identifier' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.cq_v4_pdf_chapters c WHERE c.chapter_id=p_chapter_uuid
     AND c.parent_user_id=v_uid AND c.pdf_ready IS TRUE AND c.pdf_verified_at IS NOT NULL
     AND NULLIF(pg_catalog.btrim(c.storage_path),'') IS NOT NULL)
 THEN RAISE EXCEPTION 'Verified owned PDF required' USING ERRCODE='42501'; END IF;
 SELECT chapter_uuid INTO v_existing FROM public.cq_v4_approval_requests
 WHERE id=p_approval_id AND parent_user_id=v_uid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approval not owned' USING ERRCODE='42501'; END IF;
 IF v_existing IS NOT NULL AND v_existing<>p_chapter_uuid
 THEN RAISE EXCEPTION 'Approval already bound to another chapter' USING ERRCODE='23505'; END IF;
 IF EXISTS (SELECT 1 FROM public.cq_v4_approval_requests r WHERE r.chapter_uuid=p_chapter_uuid AND r.id<>p_approval_id)
 THEN RAISE EXCEPTION 'Chapter already bound to another approval' USING ERRCODE='23505'; END IF;
 UPDATE public.cq_v4_approval_requests SET chapter_uuid=p_chapter_uuid
 WHERE id=p_approval_id AND parent_user_id=v_uid;
 RETURN p_chapter_uuid;
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_can_read_assignment(p_chapter uuid, p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_student = (select auth.uid()) and exists (
    select 1 from public.cq_v4_pdf_chapters c
    join public.cq_v4_pdf_enrollments e
      on e.parent_user_id = c.parent_user_id
     and e.student_user_id = p_student
    where c.chapter_id = p_chapter and c.pdf_ready = true
  );
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_claim_invite(p_token text, p_student_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_rows integer;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF public.cq_is_admin() THEN RAISE EXCEPTION 'Parent accounts cannot claim invitations' USING ERRCODE='42501'; END IF;
 -- Bearer-token invitation: student role is NOT inferred from cq_is_student(student_id), which uses legacy student IDs.
 -- The requesting Auth user is not enrolled until the parent explicitly approves.
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{48}$' OR
    p_student_name IS NULL OR length(pg_catalog.btrim(p_student_name)) NOT BETWEEN 1 AND 80
 THEN RAISE EXCEPTION 'Invalid invitation or name' USING ERRCODE='22023'; END IF;
 -- Serialize concurrent claims for this user and avoid racing on the partial unique index.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 927543));
 -- An enrolled child must be revoked before they can claim a fresh invitation.
 -- Avoid a unique-index error if this child already has a pending claim.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_invites i
   JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=i.parent_user_id
   WHERE i.token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND e.student_user_id=v_uid
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_invites i
   JOIN public.cq_v4_invites pending ON pending.parent_user_id=i.parent_user_id
   WHERE i.token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND pending.claimed_by=v_uid AND pending.approved_at IS NULL AND pending.revoked_at IS NULL
 ) THEN RETURN false; END IF;
 -- Concurrent claims for different tokens can race on the one-pending-child unique index.
 -- Catch only unique_violation locally so the RPC returns false rather than a raw DB error.
 BEGIN
   UPDATE public.cq_v4_invites SET claimed_by=v_uid,student_name=pg_catalog.btrim(p_student_name),claimed_at=now()
   WHERE token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND claimed_by IS NULL AND revoked_at IS NULL AND expires_at>now()
     AND parent_user_id<>v_uid;
   GET DIAGNOSTICS v_rows=ROW_COUNT;
 EXCEPTION WHEN unique_violation THEN
   RETURN false;
 END;
 RETURN v_rows=1;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_issue_invite()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_token text;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 -- Serialize concurrent issuance by this parent so the active-invitation cap is atomic.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 927541));
 IF (SELECT count(*) FROM public.cq_v4_invites
     WHERE parent_user_id=v_uid AND claimed_by IS NULL AND revoked_at IS NULL AND expires_at>now()) >= 5
 THEN RAISE EXCEPTION 'Too many active invitations' USING ERRCODE='22023'; END IF;
 v_token:=pg_catalog.encode(extensions.gen_random_bytes(24),'hex');
 INSERT INTO public.cq_v4_invites(parent_user_id,token_hash,expires_at)
 VALUES(v_uid,pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_token,'UTF8')),'hex'),now()+interval '15 minutes');
 RETURN v_token;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_list_child_access()
 RETURNS TABLE(child_user_id uuid, student_name text, active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 WITH linked AS (
   SELECT e.student_user_id AS uid
   FROM public.cq_v4_pdf_enrollments e
   WHERE e.parent_user_id=(SELECT auth.uid())
 ), pending AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.revoked_at IS NULL AND i.approved_at IS NULL
   ORDER BY i.claimed_by,i.claimed_at DESC NULLS LAST,i.created_at DESC
 ), names AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.student_name IS NOT NULL
   ORDER BY i.claimed_by,
     (i.approved_at IS NOT NULL) DESC,
     i.claimed_at DESC NULLS LAST,i.created_at DESC
 )
 SELECT ids.uid AS child_user_id,
        COALESCE(n.student_name,'연결된 학생')::text AS student_name,
        (l.uid IS NOT NULL) AS active
 FROM (SELECT uid FROM pending UNION SELECT uid FROM linked) ids
 LEFT JOIN names n ON n.uid=ids.uid
 LEFT JOIN linked l ON l.uid=ids.uid
 WHERE public.cq_is_admin();
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapter_activities(p_chapter_uuid uuid)
 RETURNS TABLE(vocabulary jsonb, writing_prompt text, speaking_prompt text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT act.vocabulary,act.writing_prompt,act.speaking_prompt
 FROM public.cq_v4_activities act
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=act.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 WHERE act.chapter_uuid=p_chapter_uuid AND a.student_user_id=(SELECT auth.uid())
   AND act.published_at IS NOT NULL AND c.pdf_ready IS TRUE;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT c.chapter_id, c.title, act.questions
 FROM public.cq_v4_pdf_chapters c
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
 WHERE a.student_user_id=(SELECT auth.uid()) AND c.pdf_ready IS TRUE
 ORDER BY c.created_at,c.chapter_id;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_submission(p_chapter_uuid uuid)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone, feedback text, feedback_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT s.chapter_uuid,s.submitted_at,
   CASE WHEN s.feedback_released THEN s.feedback ELSE NULL END,
   s.feedback_released
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id AND a.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=(SELECT auth.uid());
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_submissions()
 RETURNS TABLE(child_user_id uuid, chapter_uuid uuid, student_name text, chapter_title text, submitted_at timestamp with time zone, answers jsonb, feedback text, feedback_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT s.child_user_id, s.chapter_uuid,
         COALESCE(child_name.student_name, '연결된 학생')::text AS student_name,
         c.title AS chapter_title,
         s.submitted_at, s.answers, s.feedback, s.feedback_released
  FROM public.cq_v4_student_submissions s
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
  JOIN public.cq_v4_pdf_assignments a
    ON a.chapter_id=s.chapter_uuid AND a.student_user_id=s.child_user_id
  JOIN public.cq_v4_pdf_enrollments e
    ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
  LEFT JOIN LATERAL (
    SELECT i.student_name
    FROM public.cq_v4_invites i
    WHERE i.parent_user_id=c.parent_user_id
      AND i.claimed_by=s.child_user_id
      AND i.approved_at IS NOT NULL
      AND i.revoked_at IS NULL
      AND i.student_name IS NOT NULL
    ORDER BY i.approved_at DESC, i.created_at DESC
    LIMIT 1
  ) child_name ON true
  WHERE c.parent_user_id=(SELECT auth.uid()) AND public.cq_is_admin()
  ORDER BY s.submitted_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_publication_status(p_approval_id uuid, p_children uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_chapter uuid; v_match boolean:=false; v_missing uuid[];
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_children IS NULL OR pg_catalog.cardinality(p_children) NOT BETWEEN 1 AND 30
 OR EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE x.uid IS NULL)
 OR (SELECT pg_catalog.count(DISTINCT uid) FROM pg_catalog.unnest(p_children) AS x(uid))<>pg_catalog.cardinality(p_children)
 THEN RAISE EXCEPTION 'Invalid child list' USING ERRCODE='22023'; END IF;
 SELECT r.chapter_uuid INTO v_chapter FROM public.cq_v4_approval_requests r
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=r.chapter_uuid
 JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id
 WHERE r.id=p_approval_id AND r.parent_user_id=v_uid AND c.parent_user_id=v_uid
 AND c.pdf_ready IS TRUE AND c.pdf_verified_at IS NOT NULL
 AND a.published_at IS NOT NULL AND a.approval_id=r.id AND a.approval_hash=r.content_hash
 AND a.questions=r.questions AND a.vocabulary=r.vocabulary
 AND a.writing_prompt=r.writing_prompt AND a.speaking_prompt=r.speaking_prompt;
 v_match:=FOUND;
 SELECT pg_catalog.array_agg(x.uid ORDER BY x.uid) INTO v_missing
 FROM pg_catalog.unnest(p_children) AS x(uid)
 WHERE NOT v_match OR NOT EXISTS (
 SELECT 1 FROM public.cq_v4_pdf_assignments a
 JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=a.student_user_id
 WHERE a.chapter_id=v_chapter AND a.student_user_id=x.uid AND e.parent_user_id=v_uid);
 RETURN pg_catalog.jsonb_build_object('content_matches',v_match,'all_assigned',v_missing IS NULL,
 'missing_children',COALESCE(pg_catalog.to_jsonb(v_missing),'[]'::jsonb),'chapter_uuid',v_chapter);
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_publish_approved(p_approval_id uuid, p_children uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_r public.cq_v4_approval_requests%ROWTYPE;
        v_chapter public.cq_v4_pdf_chapters%ROWTYPE; v_current public.cq_v4_activities%ROWTYPE; v_activity_found boolean:=false;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_children IS NULL OR pg_catalog.cardinality(p_children) NOT BETWEEN 1 AND 30
 OR EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE x.uid IS NULL)
 OR (SELECT pg_catalog.count(DISTINCT uid) FROM pg_catalog.unnest(p_children) AS x(uid))<>pg_catalog.cardinality(p_children)
 THEN RAISE EXCEPTION 'Invalid child list' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_r FROM public.cq_v4_approval_requests
 WHERE id=p_approval_id AND parent_user_id=v_uid FOR UPDATE;
 IF NOT FOUND OR v_r.chapter_uuid IS NULL THEN RAISE EXCEPTION 'Approval and PDF binding required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_chapter FROM public.cq_v4_pdf_chapters
 WHERE chapter_id=v_r.chapter_uuid AND parent_user_id=v_uid AND pdf_ready IS TRUE
 AND pdf_verified_at IS NOT NULL AND NULLIF(pg_catalog.btrim(storage_path),'') IS NOT NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Verified PDF missing' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE NOT EXISTS(
 SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.parent_user_id=v_uid AND e.student_user_id=x.uid))
 THEN RAISE EXCEPTION 'Student enrollment missing' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_current FROM public.cq_v4_activities WHERE chapter_uuid=v_r.chapter_uuid FOR UPDATE;
 v_activity_found:=FOUND;
 IF v_activity_found AND v_current.published_at IS NOT NULL AND
 (v_current.approval_id IS DISTINCT FROM p_approval_id OR v_current.approval_hash IS DISTINCT FROM v_r.content_hash)
 THEN RAISE EXCEPTION 'Published content is immutable' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM public.cq_v4_student_submissions s WHERE s.chapter_uuid=v_r.chapter_uuid)
 AND (NOT v_activity_found OR v_current.approval_hash IS DISTINCT FROM v_r.content_hash)
 THEN RAISE EXCEPTION 'Cannot change content after submissions' USING ERRCODE='23505'; END IF;
 INSERT INTO public.cq_v4_activities(chapter_uuid,questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id,approval_hash)
 VALUES(v_r.chapter_uuid,v_r.questions,v_r.vocabulary,v_r.writing_prompt,v_r.speaking_prompt,now(),p_approval_id,v_r.content_hash)
 ON CONFLICT(chapter_uuid) DO UPDATE SET
 questions=EXCLUDED.questions,vocabulary=EXCLUDED.vocabulary,
 writing_prompt=EXCLUDED.writing_prompt,speaking_prompt=EXCLUDED.speaking_prompt,
 published_at=COALESCE(public.cq_v4_activities.published_at,EXCLUDED.published_at),
 approval_id=EXCLUDED.approval_id,approval_hash=EXCLUDED.approval_hash;
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id)
 SELECT v_r.chapter_uuid, x.uid FROM pg_catalog.unnest(p_children) AS x(uid)
 ON CONFLICT DO NOTHING;
 RETURN v_r.chapter_uuid;
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_register_approval_once(p_request_key uuid, p_book_id text, p_chapter_id text, p_title text, p_source text, p_questions jsonb, p_answer_key jsonb, p_vocabulary jsonb, p_writing_prompt text, p_speaking_prompt text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_id uuid; v_saved_hash text;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
 IF p_request_key IS NULL OR pg_catalog.length(pg_catalog.btrim(coalesce(p_title,'')))=0
 OR pg_catalog.length(p_title)>200 OR pg_catalog.length(pg_catalog.btrim(coalesce(p_source,'')))=0
 OR p_questions IS NULL OR jsonb_typeof(p_questions)<>'array' OR jsonb_array_length(p_questions)=0
 OR p_answer_key IS NULL OR jsonb_typeof(p_answer_key)<>'array'
 OR jsonb_array_length(p_questions)<>jsonb_array_length(p_answer_key)
 OR p_vocabulary IS NULL OR jsonb_typeof(p_vocabulary)<>'array'
 OR p_book_id IS NULL OR p_chapter_id IS NULL
 OR pg_catalog.octet_length(p_source)>1048576 THEN
 RAISE EXCEPTION 'Invalid publication payload' USING ERRCODE='22023'; END IF;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_array(p_book_id,p_chapter_id,p_title,p_source,p_questions,p_answer_key,p_vocabulary,p_writing_prompt,p_speaking_prompt)::text);
 INSERT INTO public.cq_v4_approval_requests(parent_user_id,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,content_hash)
 VALUES(v_uid,p_request_key,p_book_id,p_chapter_id,p_title,p_source,p_questions,p_answer_key,p_vocabulary,coalesce(p_writing_prompt,''),coalesce(p_speaking_prompt,''),v_hash)
 ON CONFLICT(parent_user_id,request_key) DO NOTHING;
 SELECT id,content_hash INTO v_id,v_saved_hash FROM public.cq_v4_approval_requests
 WHERE parent_user_id=v_uid AND request_key=p_request_key;
 IF v_saved_hash IS DISTINCT FROM v_hash THEN
 RAISE EXCEPTION 'Approval request key reused for different content' USING ERRCODE='23505'; END IF;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_release_feedback(p_child_user_id uuid, p_chapter_uuid uuid, p_feedback text, p_release boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_count integer;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Login required' USING ERRCODE='28000';
 END IF;
 IF p_feedback IS NULL OR pg_catalog.octet_length(p_feedback)>20000 THEN
   RAISE EXCEPTION 'Invalid feedback' USING ERRCODE='22023';
 END IF;
 IF p_release IS NULL OR (p_release AND pg_catalog.length(pg_catalog.btrim(p_feedback))=0) THEN
   RAISE EXCEPTION 'Feedback required for release' USING ERRCODE='22023';
 END IF;
 UPDATE public.cq_v4_student_submissions s
 SET feedback=p_feedback, feedback_released=p_release
 FROM public.cq_v4_pdf_chapters c
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=p_child_user_id
   AND c.chapter_id=s.chapter_uuid AND c.parent_user_id=auth.uid()
   AND a.student_user_id=s.child_user_id;
 GET DIAGNOSTICS v_count = ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'Submission not found or access denied' USING ERRCODE='42501'; END IF;
 RETURN true;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_revoke_child(p_child_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_count integer;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF p_child_user_id IS NULL OR p_child_user_id=v_uid THEN RETURN false; END IF;
 -- Serialize concurrent approval and revocation for this exact parent/child pair.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || ':' || p_child_user_id::text, 927542));
 -- Confirmed FK audit: enrollment references auth.users; no dependent FK targets enrollment.
 -- Revocation intentionally preserves student submissions and other learning records.
 DELETE FROM public.cq_v4_pdf_enrollments
 WHERE parent_user_id=v_uid AND student_user_id=p_child_user_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 UPDATE public.cq_v4_invites SET revoked_at=now()
 WHERE parent_user_id=v_uid AND claimed_by=p_child_user_id AND revoked_at IS NULL;
 RETURN v_count>0;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
 IF p_answers IS NULL OR jsonb_typeof(p_answers)<>'object' OR pg_catalog.octet_length(p_answers::text)>65536 THEN
   RAISE EXCEPTION 'Invalid answers' USING ERRCODE='22023'; END IF;
 -- Enforce the exact client payload contract; never trust hasAudio alone.
 IF p_answers->>'readComplete' IS DISTINCT FROM 'true'
    OR jsonb_typeof(p_answers->'answers') IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_answers->'answers')=0
    OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_answers->>'essay','')))=0
    OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_answers->>'speaking','')))=0
    OR p_answers->>'hasAudio' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Incomplete submission' USING ERRCODE='22023';
 END IF;
 -- Authorize the assigned, published chapter before any privileged storage lookup.
 IF NOT EXISTS (
  SELECT 1 FROM public.cq_v4_pdf_chapters c
  JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
  JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
  JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
  WHERE c.chapter_id=p_chapter_uuid AND a.student_user_id=v_uid AND c.pdf_ready IS TRUE
 ) THEN RAISE EXCEPTION 'Assignment unavailable' USING ERRCODE='42501'; END IF;
 -- Validate every answer against the authorized published question set.
 SELECT act.questions INTO v_questions FROM public.cq_v4_activities act WHERE act.chapter_uuid=p_chapter_uuid;
 IF jsonb_typeof(v_questions) IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_questions)<>jsonb_array_length(p_answers->'answers') THEN
   RAISE EXCEPTION 'Answer count mismatch' USING ERRCODE='22023';
 END IF;
 FOR v_index IN 0..jsonb_array_length(v_questions)-1 LOOP
   v_question:=v_questions->v_index;v_answer:=p_answers->'answers'->v_index;
   IF jsonb_typeof(v_answer) NOT IN ('string','number') OR v_answer IS NULL THEN
     RAISE EXCEPTION 'Invalid answer value' USING ERRCODE='22023';
   END IF;
   v_value:=v_answer #>> '{}';
   IF v_value IS NULL OR pg_catalog.length(pg_catalog.btrim(v_value))=0 OR pg_catalog.length(v_value)>8000 THEN
     RAISE EXCEPTION 'Empty or oversized answer' USING ERRCODE='22023';
   END IF;
   IF v_question->>'kind'='mc' THEN
     IF jsonb_typeof(v_question->'options') IS DISTINCT FROM 'array' OR v_value !~ '^[0-9]{1,2}$' THEN
       RAISE EXCEPTION 'Invalid multiple-choice answer' USING ERRCODE='22023';
     END IF;
     v_number:=v_value::numeric;
     IF v_number<0 OR v_number>=jsonb_array_length(v_question->'options') THEN
       RAISE EXCEPTION 'Multiple-choice answer out of range' USING ERRCODE='22023';
     END IF;
   ELSIF jsonb_typeof(v_answer) IS DISTINCT FROM 'string' THEN
     RAISE EXCEPTION 'Written answer must be text' USING ERRCODE='22023';
   END IF;
 END LOOP;
 -- Only an authorized student may probe the recording for this chapter.
 IF NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id='cq-v4-speaking'
      AND o.name IN (
        v_uid::text || '/' || p_chapter_uuid::text || '.webm',
        v_uid::text || '/' || p_chapter_uuid::text || '.mp4',
        v_uid::text || '/' || p_chapter_uuid::text || '.ogg'
      )
 ) THEN
    RAISE EXCEPTION 'Speaking recording not uploaded' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
 VALUES(p_chapter_uuid,v_uid,p_answers)
 ON CONFLICT DO NOTHING;
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_sync_legacy_device()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old_parent uuid;
begin
  if TG_OP = 'DELETE' then
    delete from public.cq_v4_pdf_enrollments
    where student_user_id = OLD.auth_user_id;
    return OLD;
  end if;
  -- Revoke old mapping whenever the device's identity, approval or status changes.
  delete from public.cq_v4_pdf_enrollments
  where student_user_id = NEW.auth_user_id;
  if TG_OP = 'UPDATE' and OLD.auth_user_id is distinct from NEW.auth_user_id then
    delete from public.cq_v4_pdf_enrollments
    where student_user_id = OLD.auth_user_id;
  end if;
  if NEW.revoked_at is null and exists (
    select 1 from public.cq_admins a where a.user_id = NEW.approved_by
  ) and NEW.approved_by <> NEW.auth_user_id then
    insert into public.cq_v4_pdf_enrollments(parent_user_id, student_user_id)
    values (NEW.approved_by, NEW.auth_user_id)
    on conflict (parent_user_id, student_user_id) do nothing;
  end if;
  return NEW;
end;
$function$;

alter table public.cq_students enable row level security;

revoke all on public.cq_students from anon,authenticated;

grant all on public.cq_students to service_role;

alter table public.cq_books enable row level security;

revoke all on public.cq_books from anon,authenticated;

grant all on public.cq_books to service_role;

alter table public.cq_chapters enable row level security;

revoke all on public.cq_chapters from anon,authenticated;

grant all on public.cq_chapters to service_role;

alter table public.cq_assignments enable row level security;

revoke all on public.cq_assignments from anon,authenticated;

grant all on public.cq_assignments to service_role;

alter table public.cq_submissions enable row level security;

revoke all on public.cq_submissions from anon,authenticated;

grant all on public.cq_submissions to service_role;

alter table public.cq_feedback enable row level security;

revoke all on public.cq_feedback from anon,authenticated;

grant all on public.cq_feedback to service_role;

alter table public.cq_student_devices enable row level security;

revoke all on public.cq_student_devices from anon,authenticated;

grant all on public.cq_student_devices to service_role;

alter table public.cq_admins enable row level security;

revoke all on public.cq_admins from anon,authenticated;

grant all on public.cq_admins to service_role;

alter table public.cq_pairing_requests enable row level security;

revoke all on public.cq_pairing_requests from anon,authenticated;

grant all on public.cq_pairing_requests to service_role;

alter table public.cq_v4_pdf_enrollments enable row level security;

revoke all on public.cq_v4_pdf_enrollments from anon,authenticated;

grant all on public.cq_v4_pdf_enrollments to service_role;

alter table public.cq_v4_pdf_chapters enable row level security;

revoke all on public.cq_v4_pdf_chapters from anon,authenticated;

grant all on public.cq_v4_pdf_chapters to service_role;

alter table public.cq_v4_pdf_assignments enable row level security;

revoke all on public.cq_v4_pdf_assignments from anon,authenticated;

grant all on public.cq_v4_pdf_assignments to service_role;

alter table public.cq_v4_snapshots enable row level security;

revoke all on public.cq_v4_snapshots from anon,authenticated;

grant all on public.cq_v4_snapshots to service_role;

alter table public.cq_v4_activities enable row level security;

revoke all on public.cq_v4_activities from anon,authenticated;

grant all on public.cq_v4_activities to service_role;

alter table public.cq_v4_student_submissions enable row level security;

revoke all on public.cq_v4_student_submissions from anon,authenticated;

grant all on public.cq_v4_student_submissions to service_role;

alter table public.cq_v4_approval_requests enable row level security;

revoke all on public.cq_v4_approval_requests from anon,authenticated;

grant all on public.cq_v4_approval_requests to service_role;

alter table public.cq_v4_invites enable row level security;

revoke all on public.cq_v4_invites from anon,authenticated;

grant all on public.cq_v4_invites to service_role;

create policy "cq_admins_select_self" on public.cq_admins as PERMISSIVE for SELECT to authenticated using ((user_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_snapshots_select" on public.cq_v4_snapshots as PERMISSIVE for SELECT to authenticated using ((owner_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_snapshots_insert" on public.cq_v4_snapshots as PERMISSIVE for INSERT to authenticated with check ((owner_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_snapshots_update" on public.cq_v4_snapshots as PERMISSIVE for UPDATE to authenticated using ((owner_id = ( SELECT auth.uid() AS uid))) with check ((owner_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_enroll_read" on public.cq_v4_pdf_enrollments as PERMISSIVE for SELECT to authenticated using (((parent_user_id = ( SELECT auth.uid() AS uid)) OR (student_user_id = ( SELECT auth.uid() AS uid))));

create policy "cq_v4_chapter_parent_read" on public.cq_v4_pdf_chapters as PERMISSIVE for SELECT to authenticated using ((parent_user_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_chapter_student_read" on public.cq_v4_pdf_chapters as PERMISSIVE for SELECT to authenticated using (((EXISTS ( SELECT 1
   FROM cq_v4_pdf_assignments a
  WHERE ((a.chapter_id = cq_v4_pdf_chapters.chapter_id) AND (a.student_user_id = ( SELECT auth.uid() AS uid))))) AND (EXISTS ( SELECT 1
   FROM cq_v4_pdf_enrollments e
  WHERE ((e.parent_user_id = cq_v4_pdf_chapters.parent_user_id) AND (e.student_user_id = ( SELECT auth.uid() AS uid))))) AND (pdf_ready = true)));

create policy "cq_v4_assignment_student_read" on public.cq_v4_pdf_assignments as PERMISSIVE for SELECT to authenticated using ((student_user_id = ( SELECT auth.uid() AS uid)));

create policy "cq_v4_speaking_insert_assigned_v1" on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'cq-v4-speaking'::text) AND (name ~ (('^'::text || (( SELECT auth.uid() AS uid))::text) || '/[0-9a-f-]{36}\.(webm|mp4|ogg)$'::text)) AND (EXISTS ( SELECT 1
   FROM ((cq_v4_pdf_chapters c
     JOIN cq_v4_pdf_assignments a ON ((a.chapter_id = c.chapter_id)))
     JOIN cq_v4_pdf_enrollments e ON (((e.parent_user_id = c.parent_user_id) AND (e.student_user_id = a.student_user_id))))
  WHERE ((a.student_user_id = ( SELECT auth.uid() AS uid)) AND (c.pdf_ready IS TRUE) AND (((objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.webm'::text)) OR (objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.mp4'::text))) OR (objects.name = ((((( SELECT auth.uid() AS uid))::text || '/'::text) || (c.chapter_id)::text) || '.ogg'::text))))))));

create policy "cq_v4_speaking_read_assigned_v1" on storage.objects as PERMISSIVE for SELECT to authenticated using (((bucket_id = 'cq-v4-speaking'::text) AND (EXISTS ( SELECT 1
   FROM ((cq_v4_pdf_chapters c
     JOIN cq_v4_pdf_assignments a ON ((a.chapter_id = c.chapter_id)))
     JOIN cq_v4_pdf_enrollments e ON (((e.parent_user_id = c.parent_user_id) AND (e.student_user_id = a.student_user_id))))
  WHERE ((((objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.webm'::text)) OR (objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.mp4'::text))) OR (objects.name = ((((a.student_user_id)::text || '/'::text) || (c.chapter_id)::text) || '.ogg'::text))) AND ((a.student_user_id = ( SELECT auth.uid() AS uid)) OR (c.parent_user_id = ( SELECT auth.uid() AS uid))))))));

grant select on public.cq_admins to authenticated;

grant select,insert,update,delete on public.cq_v4_pdf_chapters,public.cq_v4_pdf_enrollments,public.cq_v4_pdf_assignments,public.cq_v4_snapshots to authenticated;

revoke all on function public.cq_is_admin() from public,anon,authenticated;

grant execute on function public.cq_is_admin() to authenticated;

revoke all on function public.cq_v4_can_read_assignment(p_chapter uuid, p_student uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_can_read_assignment(p_chapter uuid, p_student uuid) to authenticated;

revoke all on function public.cq_v4_sync_legacy_device() from public,anon,authenticated;

revoke all on function public.cq_v4_my_chapter_activities(p_chapter_uuid uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_my_chapter_activities(p_chapter_uuid uuid) to authenticated;

revoke all on function public.cq_v4_my_submission(p_chapter_uuid uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_my_submission(p_chapter_uuid uuid) to authenticated;

revoke all on function public.cq_v4_my_chapters() from public,anon,authenticated;

grant execute on function public.cq_v4_my_chapters() to authenticated;

revoke all on function public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb) from public,anon,authenticated;

grant execute on function public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb) to authenticated;

revoke all on function public.cq_v4_register_approval_once(p_request_key uuid, p_book_id text, p_chapter_id text, p_title text, p_source text, p_questions jsonb, p_answer_key jsonb, p_vocabulary jsonb, p_writing_prompt text, p_speaking_prompt text) from public,anon,authenticated;

grant execute on function public.cq_v4_register_approval_once(p_request_key uuid, p_book_id text, p_chapter_id text, p_title text, p_source text, p_questions jsonb, p_answer_key jsonb, p_vocabulary jsonb, p_writing_prompt text, p_speaking_prompt text) to authenticated;

revoke all on function public.cq_v4_bind_verified_pdf(p_approval_id uuid, p_chapter_uuid uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_bind_verified_pdf(p_approval_id uuid, p_chapter_uuid uuid) to authenticated;

revoke all on function public.cq_v4_publish_approved(p_approval_id uuid, p_children uuid[]) from public,anon,authenticated;

grant execute on function public.cq_v4_publish_approved(p_approval_id uuid, p_children uuid[]) to authenticated;

revoke all on function public.cq_v4_publication_status(p_approval_id uuid, p_children uuid[]) from public,anon,authenticated;

grant execute on function public.cq_v4_publication_status(p_approval_id uuid, p_children uuid[]) to authenticated;

revoke all on function public.cq_v4_parent_submissions() from public,anon,authenticated;

grant execute on function public.cq_v4_parent_submissions() to authenticated;

revoke all on function public.cq_v4_release_feedback(p_child_user_id uuid, p_chapter_uuid uuid, p_feedback text, p_release boolean) from public,anon,authenticated;

grant execute on function public.cq_v4_release_feedback(p_child_user_id uuid, p_chapter_uuid uuid, p_feedback text, p_release boolean) to authenticated;

revoke all on function public.cq_v4_issue_invite() from public,anon,authenticated;

grant execute on function public.cq_v4_issue_invite() to authenticated;

revoke all on function public.cq_v4_claim_invite(p_token text, p_student_name text) from public,anon,authenticated;

grant execute on function public.cq_v4_claim_invite(p_token text, p_student_name text) to authenticated;

revoke all on function public.cq_v4_approve_child(p_child_user_id uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_approve_child(p_child_user_id uuid) to authenticated;

revoke all on function public.cq_v4_revoke_child(p_child_user_id uuid) from public,anon,authenticated;

grant execute on function public.cq_v4_revoke_child(p_child_user_id uuid) to authenticated;

revoke all on function public.cq_v4_list_child_access() from public,anon,authenticated;

grant execute on function public.cq_v4_list_child_access() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('cq-v4-originals','cq-v4-originals',false,52428800,array['application/pdf']);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('cq-v4-speaking','cq-v4-speaking',false,10485760,array['audio/webm','audio/mp4','audio/ogg','video/webm','video/mp4','application/ogg']);
