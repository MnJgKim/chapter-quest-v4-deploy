import test from 'node:test';
import assert from 'node:assert/strict';
import {previewApprovedWeek} from './approved-weekly-preview.mjs';
const parent='11111111-1111-4111-8111-111111111111',studentId='22222222-2222-4222-8222-222222222222',chapter='44444444-4444-4444-8444-444444444444',approval='55555555-5555-4555-8555-555555555555',hash='a'.repeat(64);
const scope=()=>({parentUserId:parent,studentUserId:studentId,parentAuthorized:true,studentEnrolled:true,chapters:[{parent_user_id:parent,student_user_id:studentId,chapter_id:chapter,pdf_ready:true,pdf_verified_at:'2026-11-16T00:00:00Z',published_at:'2026-11-16T00:00:00Z',approval_id:approval,approval_hash:hash}],approvals:[{parent_user_id:parent,chapter_uuid:chapter,id:approval,content_hash:hash}],assignments:[]});
const args=(readScope=async()=>scope())=>({parentUserId:parent,studentUserId:studentId,student:'서우',monday:'2026-11-23',readScope});
test('authorized server snapshot returns unreleased preview',async()=>{
 const result=await previewApprovedWeek(args());
 assert.deepEqual(result,[{parent_user_id:parent,student_user_id:studentId,chapter_id:chapter,lesson_date:'2026-11-23',release:false}]);
});
test('unauthorized parent or unenrolled student cannot preview',async()=>{
 for(const change of [{parentAuthorized:false},{studentEnrolled:false},{parentUserId:studentId},{studentUserId:parent}]){
  await assert.rejects(previewApprovedWeek(args(async()=>({...scope(),...change}))),/Unauthorized/);
 }
});
test('missing approval rows prevent a proposed assignment',async()=>{
 assert.deepEqual(await previewApprovedWeek(args(async()=>({...scope(),approvals:[]}))),[]);
});
test('missing or partial server scope fails closed',async()=>{
 await assert.rejects(previewApprovedWeek(args(async()=>null)),/Unauthorized/);
 await assert.rejects(previewApprovedWeek(args(async()=>({...scope(),assignments:undefined}))),/Unauthorized/);
});
test('existing chapter is not reissued',async()=>{
 const assignments=[{parent_user_id:parent,student_user_id:studentId,chapter_id:chapter,lesson_date:'2026-11-16'}];
 assert.deepEqual(await previewApprovedWeek(args(async()=>({...scope(),assignments}))),[]);
});
