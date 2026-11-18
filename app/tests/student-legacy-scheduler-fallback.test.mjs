import test from 'node:test';
import assert from 'node:assert/strict';
import '../public/js/student-api.js';

const chapter='33333333-3333-4333-8333-333333333333';
const url='https://example.supabase.co';
const makeApi=(schedulerResponse)=>{
 const calls=[];
 const fetchImpl=async (endpoint)=>{
   const name=endpoint.split('/').at(-1);calls.push(name);
   if(name==='cq_v4_ensure_today_approved_lesson')return schedulerResponse;
   if(name==='cq_v4_my_released_chapters')return {ok:true,json:async()=>[{chapter_uuid:chapter,chapter_title:'Lesson',questions:[{kind:'mc',text:'Question',options:['A','B']}],lesson_date:'2026-11-23'}]};
   throw Error('Unexpected RPC '+name);
 };
 return {api:globalThis.CQStudentAPI.createStudentAPI({url,anonKey:'test-public-key',getAccessToken:async()=> 'test-token',fetchImpl}),calls};
};

test('missing optional scheduler RPC still loads only server-gated released chapters',async()=>{
 const {api,calls}=makeApi({ok:false,status:404,json:async()=>({message:'Could not find the function public.cq_v4_ensure_today_approved_lesson without parameters in the schema cache'})});
 const rows=await api.assignedChapters();
 assert.equal(rows.length,1);assert.equal(rows[0].chapter_uuid,chapter);
 assert.deepEqual(calls,['cq_v4_ensure_today_approved_lesson','cq_v4_my_released_chapters']);
});

test('scheduler permission errors fail closed rather than using fallback',async()=>{
 const {api,calls}=makeApi({ok:false,status:403,json:async()=>({message:'permission denied'})});
 await assert.rejects(api.assignedChapters(),/403/);
 assert.deepEqual(calls,['cq_v4_ensure_today_approved_lesson']);
});

test('unrelated 404 errors do not bypass scheduler checks',async()=>{
 const {api,calls}=makeApi({ok:false,status:404,json:async()=>({message:'Other resource not found'})});
 await assert.rejects(api.assignedChapters(),/404/);
 assert.deepEqual(calls,['cq_v4_ensure_today_approved_lesson']);
});
