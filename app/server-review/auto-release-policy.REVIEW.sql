-- REVIEW ONLY: NOT for production execution without approval/backup.
-- Student-level opt-in and durable cancellation record for future auto releases.
-- Enrollment is the parent/student authorization source of truth.
create table if not exists public.cq_v4_auto_release_policies (
 parent_user_id uuid not null,
 student_user_id uuid not null,
 enabled boolean not null default false,
 weekdays smallint[] not null default '{}'::smallint[],
 updated_at timestamptz not null default now(),
 primary key (parent_user_id,student_user_id),
 foreign key (parent_user_id,student_user_id)
  references public.cq_v4_pdf_enrollments(parent_user_id,student_user_id)
  on delete cascade,
 constraint cq_v4_auto_release_weekdays_valid check (
  array_position(weekdays,null) is null
  and weekdays <@ array[1,2,3,4,5,6,7]::smallint[]
  and cardinality(weekdays) between 0 and 7
 )
);
-- PostgreSQL CHECK constraints cannot contain subqueries. Deduplication is
-- instead enforced by a small immutable helper.
