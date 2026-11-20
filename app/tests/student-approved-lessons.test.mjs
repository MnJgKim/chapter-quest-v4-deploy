import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadApprovedStudentLessons, requestApprovedPdfLink } from '../src/student-approved-lessons.mjs';
const chapter='33333333-3333-4333-8333-333333333333';

test('scheduler executes before authorized list; null does not hide an existing lesson', async () => {
  const calls=[];
  const rows=[{chapter_uuid:chapter,chapter_title:'Approved'}];
  const client={rpc:async name=>{calls.push(name);return name==='cq_v4_ensure_today_approved_lesson'?{data:null,error:null}:{data:rows,error:null}}};
  assert.deepEqual(await loadApprovedStudentLessons(client),rows);
  assert.deepEqual(calls,['cq_v4_ensure_today_approved_lesson','cq_v4_my_released_chapters']);
});

test('server-side scheduler rejection does not fall back to unapproved chapters', async () => {
  const calls=[];
  const client={rpc:async name=>{calls.push(name);return {data:null,error:new Error('denied')}}};
  await assert.rejects(loadApprovedStudentLessons(client),/Unable to verify/);
  assert.deepEqual(calls,['cq_v4_ensure_today_approved_lesson']);
});

test('list RPC rejection fails closed', async () => {
  const client={rpc:async name=>name==='cq_v4_ensure_today_approved_lesson'?{data:chapter,error:null}:{data:null,error:new Error('denied')}};
  await assert.rejects(loadApprovedStudentLessons(client),/Unable to load authorized/);
});

test('PDF link uses Edge Function; rejects invalid or expired responses', async () => {
  const calls=[];
  const client={functions:{invoke:async (name,args)=>{calls.push({name,args});return {data:{signed_url:'https://example.test/signed',expires_at:new Date(Date.now()+120000).toISOString()},error:null}}}};
  assert.equal((await requestApprovedPdfLink(client,chapter)).url,'https://example.test/signed');
  assert.deepEqual(calls,[{name:'cq-v4-pdf-link',args:{body:{chapter_uuid:chapter}}}]);
  await assert.rejects(requestApprovedPdfLink(client,'not-a-uuid'),/Valid chapter UUID/);
  const expired={functions:{invoke:async()=>({data:{signed_url:'https://example.test/signed',expires_at:'2020-01-01T00:00:00Z'},error:null})}};
  await assert.rejects(requestApprovedPdfLink(expired,chapter),/Invalid or expired/);
});
