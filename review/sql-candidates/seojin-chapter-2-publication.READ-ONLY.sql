-- Run before creation and after publication. Report IDs only for candidate chapters.
begin read only;
with anchor as (
  select s.parent_user_id, s.student_user_id, s.chapter_id, s.lesson_date, s.released_at
  from public.cq_v4_lesson_schedule s
  where s.chapter_id = '1dcf0d1f-c048-4e3a-bb7e-3d05c4600143'
    and s.lesson_date = date '2026-11-24'
), book as (
  select distinct r.book_local_id
  from public.cq_v4_approval_requests r
  join anchor a on a.chapter_id = r.chapter_uuid and a.parent_user_id = r.parent_user_id
), candidates as (
  select p.chapter_id, p.pdf_ready, p.pdf_verified_at, o.id is not null as pdf_object_exists,
         coalesce(o.metadata->>'size' = '11937462', false) as pdf_size_matches
  from public.cq_v4_pdf_chapters p
  left join storage.objects o on o.bucket_id = 'cq-v4-originals' and o.name = p.storage_path
  where p.parent_user_id in (select parent_user_id from anchor)
    and p.chapter_id not in (select chapter_id from anchor)
    and (p.title ~* '(29[-_ ]2|chapter[ _-]*0?2([^0-9]|$))'
         or o.metadata->>'size' = '11937462'
         or exists (
           select 1 from public.cq_v4_approval_requests r
           where r.chapter_uuid = p.chapter_id and r.parent_user_id = p.parent_user_id
             and r.book_local_id in (select book_local_id from book)
             and r.title ~* '(29[-_ ]2|chapter[ _-]*0?2([^0-9]|$))'
         ))
)
select (select count(*) from anchor) as chapter_1_anchor_count,
       (select count(*) from anchor where released_at is not null) as chapter_1_release_flag_count,
       (select count(*) from public.cq_v4_lesson_schedule s join anchor a using (parent_user_id, student_user_id)
        where s.lesson_date = date '2026-11-25' and s.chapter_id not in
          (select chapter_id from candidates)) as other_nov_25_slots,
       (select count(*) from candidates) as candidate_count,
       coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object(
         'approval_ids', (select coalesce(jsonb_agg(r.id), '[]'::jsonb)
                          from public.cq_v4_approval_requests r
                          where r.chapter_uuid = c.chapter_id
                            and r.parent_user_id in (select parent_user_id from anchor)
                            and r.content_hash is not null),
         'activity_published', exists (select 1 from public.cq_v4_activities v
                                       where v.chapter_uuid = c.chapter_id and v.published_at is not null),
         'assignment_count', (select count(*) from public.cq_v4_pdf_assignments x
                              where x.chapter_id = c.chapter_id),
         'target_assignment_count', (select count(*) from public.cq_v4_pdf_assignments x
                                     join anchor a using (student_user_id)
                                     where x.chapter_id = c.chapter_id),
         'target_schedule', (select jsonb_agg(jsonb_build_object(
            'lesson_date', s.lesson_date, 'timezone', s.timezone,
            'release_enabled', s.released_at is not null,
            'earliest_date_gate_utc', case when s.released_at is not null and s.timezone = 'Asia/Seoul'
              then to_char(s.lesson_date::timestamp - interval '9 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') end))
            from public.cq_v4_lesson_schedule s join anchor a using (parent_user_id, student_user_id)
            where s.chapter_id = c.chapter_id)
       )) from candidates c), '[]'::jsonb) as candidates;
rollback;
