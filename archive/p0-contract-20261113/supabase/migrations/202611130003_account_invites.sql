begin;
create table cq_private.account_invites(parent_user_id uuid not null references public.cq_v4_profiles(user_id),email_hash bytea not null,created_at timestamptz not null default now());
create function public.cq_v4_reserve_account_invite(p_email text) returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=cq_private.require_role('parent'); begin
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'INVALID_EMAIL'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,1));
 if (select count(*) from cq_private.account_invites where parent_user_id=u and created_at>now()-interval '1 hour')>=10 then raise exception 'ACCOUNT_INVITE_RATE_LIMIT'; end if;
 insert into cq_private.account_invites values(u,sha256(convert_to(lower(trim(p_email)),'UTF8')),now()); return true;
end $$;
revoke all on function public.cq_v4_reserve_account_invite(text) from public,anon;
grant execute on function public.cq_v4_reserve_account_invite(text) to authenticated;
commit;
