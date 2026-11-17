import test from 'node:test';
import assert from 'node:assert/strict';
import {proposeFromScopedRows} from './approved-weekly-adapter.mjs';
const parent='11111111-1111-4111-8111-111111111111';
const child='22222222-2222-4222-8222-222222222222';
const chapter='44444444-4444-4444-8444-444444444444';
const approval='55555555-5555-4555-8555-555555555555';
const row=()=>({parent_user_id:parent,student_user_id:child,chapter_id:chapter,pdf_ready:true,pdf_verified_at:'2026-11-16T00:00:00Z',published_at:'2026-11-16T01:00:00Z',approval_id:approval,approval_hash:'a'.repeat(64),approval_verified:true});
const input=(overrides={})=>({student:'서우',parentUserId:parent,studentUserId:child,monday:'2026-11-23',chapters:[row()],assignments:[],...overrides});
test('scoped verified content produces unreleased dated proposal',()=>{
 assert.deepEqual(proposeFromScopedRows(input()),[{parent_user_id:parent,student_user_id:child,chapter_id:chapter,lesson_date:'2026-11-23',release:false}]);
});
test('no approval proof means no assignment',()=>{
 for(const change of [{approval_verified:false},{approval_id:null},{approval_hash:null},{published_at:null},{pdf_ready:false},{pdf_verified_at:null}]){
  assert.deepEqual(proposeFromScopedRows(input({chapters:[{...row(),...change}]})),[]);
 }
});
test('foreign parent or student content is never proposed',()=>{
 for(const change of [{parent_user_id:child},{student_user_id:parent}]){
  assert.deepEqual(proposeFromScopedRows(input({chapters:[{...row(),...change}]})),[]);
 }
});
test('existing assigned chapter is not proposed again',()=>{
 assert.deepEqual(proposeFromScopedRows(input({assignments:[{parent_user_id:parent,student_user_id:child,chapter_id:chapter,lesson_date:'2026-11-16'}]})),[]);
});
test('foreign or malformed assignment list fails closed',()=>{
 assert.throws(()=>proposeFromScopedRows(input({assignments:[{parent_user_id:child,student_user_id:child,chapter_id:chapter,lesson_date:'2026-11-23'}]})),/scope mismatch/);
 assert.throws(()=>proposeFromScopedRows(input({assignments:[{parent_user_id:parent,student_user_id:child,chapter_id:chapter,lesson_date:'2026-02-30'}]})),/scope mismatch/);
});
test('untrusted identifiers cannot request proposals',()=>{
 assert.throws(()=>proposeFromScopedRows(input({studentUserId:'서우'})),/scope required/);
});

test('duplicate approval evidence is rejected instead of choosing a row',()=>{
 assert.throws(()=>proposeFromScopedRows(input({chapters:[row(),{...row(),approval_verified:false}]})),/Duplicate chapter evidence/);
});
test('no candidate can be inferred from missing approval verification',()=>{
 const unverified=row();delete unverified.approval_verified;
 assert.deepEqual(proposeFromScopedRows(input({chapters:[unverified]})),[]);
});
