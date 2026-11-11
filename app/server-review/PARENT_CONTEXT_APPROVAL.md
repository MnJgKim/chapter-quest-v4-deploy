# Additive parent lesson read API — production approval required

Proposed SQL: `../local-supabase/supabase/migrations/20261111013217_cq_parent_lesson_context.sql`. The authoritative repository path is `app/local-supabase/supabase/migrations/20261111013217_cq_parent_lesson_context.sql`.

This adds only `public.cq_v4_parent_lesson(uuid)`. It returns a registered parent's own published questions, model answer key, vocabulary and writing/speaking prompts so submitted numeric choices can be displayed as actual choices in the parent results screen. It does not update or delete existing data, accounts, tables, policies, functions or storage objects.

The function requires a non-null `auth.uid()`, the existing authoritative `cq_is_admin()` result, and exact chapter ownership. It uses `SECURITY DEFINER` only to read private tables that intentionally have no client SELECT grant; its search path is empty and all application references are schema-qualified. EXECUTE is revoked from PUBLIC/anon and granted to authenticated; students are still denied by the function's admin check. Another registered parent receives no row for an unowned chapter. User-editable metadata never authorizes access.

Before an approved application, verify the target project ref and confirm this function does not already exist. The script deliberately uses `CREATE FUNCTION` so an unexpected existing function is not overwritten. Apply **only this reviewed file**; the adjacent `cq_local_schema` migration is a local test bootstrap and must never be run on production. Check advisors and repeat role/ownership reads after the approved change, plus data fingerprints before/after.

Rollback for this new API is `DROP FUNCTION public.cq_v4_parent_lesson(uuid);` only after confirming it is the function created by this release. It does not require any row rollback. The frontend retains a local-draft/raw-submission fallback when the function is unavailable, and the prior Cloudflare version can independently be restored. Do not apply the older historical submission/role rollback scripts.

This proposal is implemented and tested locally only. It has not been applied to the hosted project. Operating deployment and this function addition both require explicit user approval.
