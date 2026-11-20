// Focused regression for the submit-vs-parent-reschedule lock contract.
// Run separately: node --test app/tests/makeup-submission-lock.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const schedule=readFileSync(new URL('../sql/makeup-approval-v1.REVIEW-ONLY.sql',import.meta.url),'utf8');
const submit=readFileSync(new URL('../sql/lesson-day-rpc-storage-v3.REVIEW-ONLY.sql',import.meta.url),'utf8');
test('parent and student take identical transaction-scoped advisory lock',()=>{
  assert.match(schedule,/pg_advisory_xact_lock\(pg_catalog\.hashtextextended\(p_student_user_id::text \|\| ':' \|\| p_chapter_id::text, 0\)\)/);
  assert.match(submit,/pg_advisory_xact_lock\(pg_catalog\.hashtextextended\(v_uid::text \|\| ':' \|\| p_chapter_uuid::text, 0\)\)/);
});
test('lock precedes mutable state reads on both RPCs',()=>{
  assert.ok(schedule.indexOf('pg_advisory_xact_lock') < schedule.indexOf('SELECT 1 FROM public.cq_v4_student_submissions done'));
  assert.ok(submit.indexOf('pg_advisory_xact_lock') < submit.indexOf('IF EXISTS (SELECT 1 FROM public.cq_v4_student_submissions existing'));
  assert.ok(submit.indexOf('pg_advisory_xact_lock') < submit.indexOf('cq_v4_can_start_lesson(p_chapter_uuid,v_uid)'));
});
