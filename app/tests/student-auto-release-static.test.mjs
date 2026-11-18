import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const sql=fs.readFileSync(new URL('../sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql',import.meta.url),'utf8');

test('candidate is scoped to one authenticated student and Seoul lesson date',()=>{
 for(const fragment of [
  'SECURITY DEFINER', "SET search_path TO ''", '(SELECT auth.uid())',
  "AT TIME ZONE 'Asia/Seoul'", 's.lesson_date = v_today',
  "s.timezone = 'Asia/Seoul'", 'pg_advisory_xact_lock',
  'v_count <> 1', 's.released_at IS NULL',
  'cq_v4_student_weekday_policy', 'p.enabled IS TRUE', 'p.effective_from <= v_today',
  'EXTRACT(ISODOW FROM v_today)', 'ANY(v_weekdays)',
  'count(DISTINCT s.chapter_id)', 'cq_v4_student_submissions',
  'cq_v4_pdf_assignments','cq_v4_pdf_enrollments','cq_v4_pdf_chapters','cq_v4_activities',
  'GRANT EXECUTE ON FUNCTION public.cq_v4_ensure_today_approved_lesson() TO authenticated'
 ]) assert.ok(sql.includes(fragment), 'missing: '+fragment);
 assert.doesNotMatch(sql,/\b(?:DELETE|TRUNCATE|DROP)\b/i);
 assert.doesNotMatch(sql,/\bINSERT\s+INTO\s+public\.cq_v4_(?:pdf_assignments|lesson_schedule)/i);
 assert.match(sql,/UPDATE public\.cq_v4_lesson_schedule s\s+SET released_at = now\(\)/);
});

test('no implicit weekday defaults, no schedule/assignment changes, no reopening submissions',()=>{
 assert.match(sql,/IF v_weekdays IS NULL OR NOT/);
 assert.match(sql,/IF v_count <> 1 THEN/);
 assert.match(sql,/NOT EXISTS \(\s*SELECT 1 FROM public\.cq_v4_student_submissions sub/g);
 assert.doesNotMatch(sql,/\bUPDATE\s+public\.cq_v4_(?:pdf_assignments|student_submissions)\b/i);
 assert.doesNotMatch(sql,/\bINSERT\s+INTO\b/i);
 assert.doesNotMatch(sql,/\bUPDATE\s+public\.cq_v4_lesson_schedule\s+SET\s+lesson_date\b/i);
});
