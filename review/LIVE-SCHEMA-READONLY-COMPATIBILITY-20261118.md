# Chapter Quest V4 — Connected Supabase metadata audit (2026-11-18)

READ-ONLY OBSERVATION. No SQL DDL/DML, migrations, production writes, auth logins, student assignments, or deployments were performed.

## Target identity caveat

Connected Supabase project listing returned one ACTIVE_HEALTHY project named `english-v3b-test` and one inactive project. The active project was inspected only via metadata queries; **its status as the Chapter Quest V4 production project is not confirmed**. Do not infer target identity from activity or table names.

## Inspected schema (no user answers, IDs or tokens read)

- `public.cq_v4_activities`: `chapter_uuid uuid`, `questions jsonb`, `approval_id uuid`, `approval_hash text`, `published_at timestamptz`.
- `public.cq_v4_approval_requests`: `id uuid`, `chapter_uuid uuid`, `parent_user_id uuid`, `answer_key jsonb`, `content_hash text`.
- `public.cq_v4_student_submissions`: `chapter_uuid uuid`, `child_user_id uuid`, `answers jsonb`, `submitted_at timestamptz`, `feedback_released boolean NOT NULL`.
- Enrollment, assignment, and chapter ownership join columns are present with expected UUID types.
- Observed question keys: `kind`, `options`, `text`; observed kinds: `mc`, `short`, `inference`.
- Approval answer keys are JSON arrays with numeric elements in existing records; submission JSON is an object with an `answers` array plus reading/writing/speaking metadata fields.
- `cq_v4_reread_notices` was not present in public table metadata at inspection time. REVIEW-ONLY candidate was **not installed**.

## Open compatibility and security questions

1. **Immutable approval snapshot:** current candidate joins current `activities` and `approval_requests`, not a permanently frozen submission-time snapshot. A later approval change could affect score or cause a denial. Resolve before deployment.
2. **Snapshot linkage:** inspect only catalog constraints/indexes and RLS before any migration; the metadata checks above do not prove every existing record is joinable.
3. **Student score privacy:** Boolean RPC returns no score or key; inspect privilege grants, function owner and security definer execution context before deployment.
4. **Hosted function availability:** none of the new RPCs were deployed; browser fallback is expected.
5. **Read-only trap:** student chapter listing may invoke an auto-assignment RPC. Do not test this against live student data without approval.
6. **Version mismatch:** CI PostgreSQL 16 isolation vs connected Supabase PostgreSQL 17; hosted behavior is unverified.

## Next non-mutating checks

Verify exact intended production project ref via existing deployment configuration (without exposing credentials); compare `pg_proc` function signatures and catalog constraints, roles, and policies. Keep all changes in development branch. No production deployment, student login, device tests or writes were performed.
