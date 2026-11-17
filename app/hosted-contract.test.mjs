import test from 'node:test';
import assert from 'node:assert/strict';
import {REQUIRED,auditHostedInventory,auditStudentSchedule} from './hosted-contract.mjs';
test('full object inventory is not a deployment authorization',()=>{const result=auditHostedInventory(REQUIRED);assert.equal(result.objectsPresent,true);assert.equal(result.hostedReady,false);assert.equal(result.safeToDeploy,false)});
test('missing storage bucket is reported',()=>{const result=auditHostedInventory({...REQUIRED,buckets:['cq-v4-originals']});assert.deepEqual(result.missing.buckets,['cq-v4-speaking'])});
test('invalid inventory fails closed',()=>assert.throws(()=>auditHostedInventory({...REQUIRED,functions:['']}),/Invalid functions/));
test('weekly defaults match Seowoo and Seojin',()=>assert.equal(auditStudentSchedule([{student:'서우',days:[1,3,4]},{student:'서진',days:[2,3,5]}]).valid,true));
test('schedule errors do not silently pass',()=>assert.equal(auditStudentSchedule([{student:'서우',days:[1,4]},{student:'서진',days:[2,3,5]}]).valid,false));