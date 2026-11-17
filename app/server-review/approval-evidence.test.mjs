import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyChapterApproval} from './approval-evidence.mjs';
import {proposeFromScopedRows} from './approved-weekly-adapter.mjs';
const parent='11111111-1111-4111-8111-111111111111',student='22222222-2222-4222-8222-222222222222';
const chapter='44444444-4444-4444-8444-444444444444',id='55555555-5555-4555-8555-555555555555',hash='a'.repeat(64);
const c=()=>({parent_user_id:parent,student_user_id:student,chapter_id:chapter,approval_id:id,approval_hash:hash,pdf_ready:true,pdf_verified_at:'2026-11-16T00:00:00Z',published_at:'2026-11-16T00:00:00Z',approval_verified:true});
const a=()=>({parent_user_id:parent,chapter_uuid:chapter,id,content_hash:hash});
const verified=(chapters=[c()],approvals=[a()])=>verifyChapterApproval({parentUserId:parent,studentUserId:student,chapters,approvals});
test('valid matching approval is independently verified',()=>{
 assert.equal(verified()[0].approval_verified,true);
 const proposals=proposeFromScopedRows({student:'서우',studentUserId:student,parentUserId:parent,monday:'2026-11-23',chapters:verified(),assignments:[]});
 assert.equal(proposals.length,1);
 assert.equal(proposals[0].release,false);
});
test('browser-provided approval_verified true cannot override missing DB record',()=>{
 assert.equal(verified([c()],[])[0].approval_verified,false);
});
test('hash, approval id, parent, chapter mismatch fail closed',()=>{
 for(const change of [{content_hash:'b'.repeat(64)},{id:chapter},{parent_user_id:student},{chapter_uuid:id}]){
  assert.equal(verified([c()],[{...a(),...change}])[0].approval_verified,false);
 }
});
test('ambiguous duplicate approvals fail closed',()=>{
 assert.equal(verified([c()],[a(),a()])[0].approval_verified,false);
});
test('wrong student scope fails closed',()=>{
 assert.equal(verified([{...c(),student_user_id:parent}])[0].approval_verified,false);
});
