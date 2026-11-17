import test from 'node:test';import assert from 'node:assert/strict';import {validateTestAssignment as check,TEST_UID} from './test-assignment-guard.mjs';
const base={chapter:{uuid:'chapter-3',ready:true},studentId:TEST_UID,students:[{student_user_id:TEST_UID}],children:[{child_user_id:TEST_UID,active:true}],assignments:[]};
test('only test student accepted',()=>assert.deepEqual(check(base),{chapter_uuid:'chapter-3',student_user_id:TEST_UID}));
test('reject actual student',()=>assert.throws(()=>check({...base,studentId:'actual-student'}),/test account/));
test('reject unverified PDF',()=>assert.throws(()=>check({...base,chapter:{uuid:'chapter-3',ready:false}}),/verified/));
test('reject inactive link',()=>assert.throws(()=>check({...base,children:[{child_user_id:TEST_UID,active:false}]}),/linked/));
test('reject absent student',()=>assert.throws(()=>check({...base,students:[]}),/server list/));
test('reject duplicate',()=>assert.throws(()=>check({...base,assignments:[{chapter_uuid:'chapter-3',student_user_id:TEST_UID}]}),/already assigned/));
test('reject missing snapshot',()=>assert.throws(()=>check({...base,assignments:undefined}),/already assigned/));
