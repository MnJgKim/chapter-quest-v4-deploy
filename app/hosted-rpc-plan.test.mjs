import test from 'node:test';
import assert from 'node:assert/strict';
import {buildParentRpcPlan} from './hosted-rpc-plan.mjs';
const child='11111111-1111-4111-8111-111111111111', chapter='22222222-2222-4222-8222-222222222222', chapter2='33333333-3333-4333-8333-333333333333';
const plan=(proposed)=>buildParentRpcPlan({proposed,studentUserIds:{'서우':child}});
test('produces existing parent RPC contract only',()=>{const r=plan([{student:'서우',lessonDate:'2026-11-23',chapterId:chapter}]);assert.equal(r.calls[0].rpc,'cq_v4_parent_schedule_lesson');assert.equal(r.calls[0].args.p_lesson_date,'2026-11-23');assert.deepEqual(r.releaseCalls,[]);assert.equal(r.executable,false);assert.equal(r.writesPerformed,0)});
test('missing student UUID is rejected',()=>assert.throws(()=>plan([{student:'서진',lessonDate:'2026-11-24',chapterId:chapter}]),/Invalid hosted/));
test('non UUID chapter is rejected',()=>assert.throws(()=>plan([{student:'서우',lessonDate:'2026-11-23',chapterId:'demo'}]),/Invalid hosted/));
test('duplicate lesson date is rejected',()=>assert.throws(()=>plan([{student:'서우',lessonDate:'2026-11-23',chapterId:chapter},{student:'서우',lessonDate:'2026-11-23',chapterId:chapter2}]),/Duplicate/));
test('approval flag does not enable execution',()=>{const r=buildParentRpcPlan({proposed:[],studentUserIds:{},parentApproved:true});assert.equal(r.executable,false);assert.equal(r.requiresLivePreflight,true)});

test('wrong student weekday is rejected',()=>assert.throws(()=>plan([{student:'서우',lessonDate:'2026-11-24',chapterId:chapter}]),/weekday/));
test('same chapter across two allowed dates is rejected',()=>assert.throws(()=>plan([{student:'서우',lessonDate:'2026-11-23',chapterId:chapter},{student:'서우',lessonDate:'2026-11-25',chapterId:chapter}]),/Duplicate student chapter/));

test('shared UUID between students is rejected',()=>assert.throws(()=>buildParentRpcPlan({proposed:[],studentUserIds:{'서우':child,'서진':child}}),/share an account/));
test('malformed date rejects with TypeError',()=>assert.throws(()=>plan([{student:'서우',lessonDate:'2026-99-99',chapterId:chapter}]),/Invalid hosted assignment/));
