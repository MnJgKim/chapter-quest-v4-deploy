// Targeted AI safety/readiness checks. No hosted calls, credentials, or billable inference.
import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';
const req=(method='POST')=>new Request('https://chapter-quest.invalid/api/generate',{
 method,headers:{'content-type':'application/json','authorization':'Bearer offline-token'},
 ...(method==='POST'?{body:JSON.stringify({source:'A simple story. '.repeat(30)})}:{})
});
test('disabled AI refuses generation before auth or inference even with a model binding',async()=>{
 let invoked=0;
 const response=await worker.fetch(req(),{
 AI_FREE_PLAN_CONFIRMED:'false',SUPABASE_URL:'https://example.supabase.co',
 SUPABASE_PUBLISHABLE_KEY:'offline',AI:{run:async()=>{invoked++;throw Error('should never run');}}
 });
 assert.equal(response.status,503);assert.equal(invoked,0);
 assert.match((await response.json()).error,/AI 서버 연결/);
});
test('AI health endpoint does not report ready while free-plan confirmation is false',async()=>{
 const response=await worker.fetch(new Request('https://chapter-quest.invalid/api/health'),{
 AI_FREE_PLAN_CONFIRMED:'false',SUPABASE_URL:'https://example.supabase.co',
 SUPABASE_PUBLISHABLE_KEY:'offline',AI:{run:async()=>{throw Error('never run')}}
 });
 assert.equal(response.status,200);assert.equal((await response.json()).aiConfigured,false);
});
