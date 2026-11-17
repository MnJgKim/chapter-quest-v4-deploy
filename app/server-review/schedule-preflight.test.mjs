import test from 'node:test';
import assert from 'node:assert/strict';
import {preflightSchedule} from './schedule-preflight.mjs';
const parent='11111111-1111-4111-8111-111111111111',student='22222222-2222-4222-8222-222222222222';
const a='44444444-4444-4444-8444-444444444444',b='55555555-5555-4555-8555-555555555555';
const proposal=(chapter_id=a,lesson_date='2026-11-23')=>({parent_user_id:parent,student_user_id:student,chapter_id,lesson_date,release:false});
const existing=(chapter_id=a,lesson_date='2026-11-16')=>({parent_user_id:parent,student_user_id:student,chapter_id,lesson_date});
const check=(proposals,rows=[])=>preflightSchedule({parentUserId:parent,studentUserId:student,proposals,existing:rows});
test('valid proposals are copied without mutating source',()=>{const input=[proposal()];assert.deepEqual(check(input),input);assert.notEqual(check(input)[0],input[0]);});
test('existing chapter cannot be assigned again',()=>assert.throws(()=>check([proposal()], [existing()]),/collision/));
test('existing lesson date cannot be overwritten',()=>assert.throws(()=>check([proposal(b)], [existing(a,'2026-11-23')]),/collision/));
test('duplicate dates and chapters in batch fail',()=>{
 assert.throws(()=>check([proposal(),proposal(b)]),/collision/);
 assert.throws(()=>check([proposal(),proposal(a,'2026-11-25')]),/collision/);
});
test('release request, foreign scope, invalid date are rejected',()=>{
 for(const change of [{release:true},{parent_user_id:student},{student_user_id:parent},{lesson_date:'2026-02-30'}]){
  assert.throws(()=>check([{...proposal(),...change}]),/Invalid/);
 }
});
test('foreign existing assignments fail closed',()=>assert.throws(()=>check([proposal()],[{...existing(),parent_user_id:student}]),/scope/));
