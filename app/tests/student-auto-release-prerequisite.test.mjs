import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const prerequisite=fs.readFileSync(new URL('../sql/student-weekday-policy-and-approved-queue.REVIEW-ONLY.sql',import.meta.url),'utf8');
const release=fs.readFileSync(new URL('../sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql',import.meta.url),'utf8');
test('weekday policy validates ISO days and ownership',()=>{
 for(const part of ['cq_v4_student_weekday_policy','cardinality(weekdays) BETWEEN 1 AND 7','ARRAY[1,2,3,4,5,6,7]','cq_v4_parent_set_weekdays','cq_v4_pdf_enrollments','pg_advisory_xact_lock'])
 assert.ok(prerequisite.includes(part),part);
});
test('queue enforces ordering, parent authorization and published assigned PDFs',()=>{
 for(const part of ['cq_v4_approved_chapter_queue','UNIQUE(student_user_id,queue_position)','cq_v4_parent_queue_approved_chapter','cq_v4_pdf_assignments','cq_v4_activities','act.published_at IS NOT NULL','cq_v4_next_approved_chapter'])
 assert.ok(prerequisite.includes(part),part);
});
test('RLS and RPC grants do not permit direct student writes',()=>{
 assert.match(prerequisite,/ENABLE ROW LEVEL SECURITY/g);
 assert.match(prerequisite,/REVOKE ALL ON public\.cq_v4_student_weekday_policy/);
 assert.doesNotMatch(prerequisite,/GRANT (?:INSERT|UPDATE|DELETE|ALL) ON public\.cq_v4_/i);
});
test('release uses Seoul day, existing schedule precedence, student lock, and pause',()=>{
 for(const part of ["AT TIME ZONE 'Asia/Seoul'",'EXTRACT(ISODOW FROM v_today)','pg_advisory_xact_lock','v_schedule.chapter_id IS NOT NULL','NOT s.auto_release_paused','cq_v4_next_approved_chapter(v_student)','ON CONFLICT (student_user_id, chapter_id) DO NOTHING'])
 assert.ok((release+prerequisite).includes(part),part);
});
test('migration is review only and does not seed or overwrite existing lessons',()=>{
 assert.doesNotMatch(prerequisite,/\b(?:TRUNCATE|DELETE FROM public\.cq_v4_|INSERT INTO public\.cq_v4_lesson_schedule)\b/i);
 assert.match(prerequisite,/BEGIN;/);assert.match(prerequisite,/COMMIT;/);
});
