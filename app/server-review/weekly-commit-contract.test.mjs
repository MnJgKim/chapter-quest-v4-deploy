import test from 'node:test';
import assert from 'node:assert/strict';
import {commitWeeklyAtomically} from './weekly-commit-contract.mjs';
const parent='11111111-1111-4111-8111-111111111111',student='22222222-2222-4222-8222-222222222222',chapter='44444444-4444-4444-8444-444444444444';
const proposal=()=>({parent_user_id:parent,student_user_id:student,chapter_id:chapter,lesson_date:'2026-11-23',release:false});
const args=(proposals,atomicWriter)=>({parentUserId:parent,studentUserId:student,proposals,atomicWriter});
test('valid batch is delegated once to atomic writer',async()=>{
 let calls=0;
 const result=await commitWeeklyAtomically(args([proposal()],async({proposals})=>{calls++;assert.equal(proposals.length,1);return {inserted:1};}));
 assert.equal(calls,1);assert.deepEqual(result,{inserted:1});
});
test('empty proposals never invoke writer',async()=>{
 const result=await commitWeeklyAtomically(args([],async()=>{throw Error('must not write');}));
 assert.deepEqual(result,{inserted:0,skipped:true});
});
test('duplicate or released proposals never reach writer',async()=>{
 let calls=0;const writer=async()=>{calls++;};
 await assert.rejects(commitWeeklyAtomically(args([proposal(),proposal()],writer)),/collision/);
 await assert.rejects(commitWeeklyAtomically(args([{...proposal(),release:true}],writer)),/Invalid/);
 assert.equal(calls,0);
});
test('missing atomic writer is rejected',async()=>{
 await assert.rejects(commitWeeklyAtomically(args([proposal()],null)),/Trusted atomic writer/);
});
test('writer failure is propagated, not reported as success',async()=>{
 await assert.rejects(commitWeeklyAtomically(args([proposal()],async()=>{throw Error('transaction conflict');})),/transaction conflict/);
});
