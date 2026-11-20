-- DEVELOPMENT ONLY. Do not apply to production without explicit approval.
-- Validate an authoritative, matching approval before publishing any new chapter.
-- This is a publication-time guard, NOT per-chapter reread configuration.
-- Legacy published chapters remain unchanged; no backfill is attempted.
create or replace function public.cq_v4_assert_reread_publishable(p_approval_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $function$
declare v_questions jsonb; v_key jsonb; v_count integer:=0; v_i integer; v_q jsonb; v_answer text;
begin
 if auth.uid() is null or not public.cq_is_admin() then
   raise exception 'Parent authorization required' using errcode='42501';
 end if;
 select r.questions,r.answer_key into v_questions,v_key
 from public.cq_v4_approval_requests r
 where r.id=p_approval_id and r.parent_user_id=auth.uid();
 if not found or jsonb_typeof(v_questions) is distinct from 'array'
    or jsonb_typeof(v_key) is distinct from 'array'
    or jsonb_array_length(v_questions)<>jsonb_array_length(v_key) then
   raise exception 'Approved questions and answer key are missing or mismatched' using errcode='22023';
 end if;
 if jsonb_array_length(v_questions)>0 then
  for v_i in 0..jsonb_array_length(v_questions)-1 loop
   v_q:=v_questions->v_i;
   if v_q->>'kind' <> 'mc' then continue; end if;
   v_count:=v_count+1;
   v_answer:=v_key->>v_i;
   if jsonb_typeof(v_q->'options') is distinct from 'array'
      or jsonb_array_length(v_q->'options')<2
      or jsonb_typeof(v_key->v_i) is distinct from 'number'
      or v_answer is null
      or v_answer = ''
      or pg_catalog.translate(v_answer,'0123456789','') <> ''
      or (pg_catalog.length(v_answer)>1 and pg_catalog.left(v_answer,1)='0')
      or pg_catalog.length(v_answer)>9
      then
      raise exception 'Invalid multiple-choice answer key at index %',v_i using errcode='22023';
   end if;
   -- Do not cast until the preceding statement has validated numeric syntax.
   if v_answer::integer>=jsonb_array_length(v_q->'options') then
      raise exception 'Multiple-choice key out of range at index %',v_i using errcode='22023';
   end if;
  end loop;
 end if;
 if v_count=0 then
  raise exception 'No objectively scorable multiple-choice questions' using errcode='22023';
 end if;
 return true;
end;
$function$;
revoke all on function public.cq_v4_assert_reread_publishable(uuid) from public,anon;
grant execute on function public.cq_v4_assert_reread_publishable(uuid) to authenticated;
-- Integration point for a reviewed cq_v4_publish_approved migration:
-- PERFORM public.cq_v4_assert_reread_publishable(p_approval_id);
-- Execute inside the SAME publication transaction before writing activities.
-- Do not change production publication RPC until separate approval.
