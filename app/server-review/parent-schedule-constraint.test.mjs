import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const migration=readFileSync(new URL('./parent-schedule-student-day-unique.REVIEW.sql',import.meta.url),'utf8');
const audit=readFileSync(new URL('./parent-schedule-notice-readonly-audit.sql',import.meta.url),'utf8');
test('schedule collision migration adds student/day unique index without modifying lessons',()=>{
 const active=migration.split('\n').filter(line=>!line.trim().startsWith('--')).join('\n');
 assert.match(active,/CREATE UNIQUE INDEX cq_v4_lesson_schedule_student_day_unique\s+ON public\.cq_v4_lesson_schedule\s*\(student_user_id, lesson_date\)/);
 assert.doesNotMatch(active,/\b(?:DELETE|UPDATE|TRUNCATE|DROP|ALTER TABLE)\b/i);
 assert.match(audit,/having count\(\*\)>1/i);
});
test('notice RPC audit explicitly checks both parent RPC names',()=>{
 assert.match(audit,/cq_v4_parent_reread_inbox/);
 assert.match(audit,/cq_v4_parent_ack_reread_notice/);
});
