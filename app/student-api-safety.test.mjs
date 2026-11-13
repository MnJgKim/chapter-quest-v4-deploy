import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const source = await fs.readFile(new URL('./public/js/student-api.js', import.meta.url), 'utf8');
const chapter = '44444444-4444-4444-8444-444444444444';
function client({responses={}, token='student-token', calls=[]}={}) {
  const context = vm.createContext({URL, AbortController, DOMException, fetch:()=>{throw Error('Unexpected network')}});
  vm.runInContext(source,context);
  const fetchImpl=async (url,options)=>{
    calls.push({url,options});
    const name=url.split('/').pop();
    return {ok:true,json:async()=>responses[name]??[]};
  };
  return context.CQStudentAPI.createStudentAPI({
    url:'https://example.supabase.co',anonKey:'public-anon',
    getAccessToken:async()=>token,fetchImpl
  });
}
test('student chapter transport strips answer keys and parent-only evidence',async()=>{
  const api=client({responses:{cq_v4_my_chapters:[{
    chapter_uuid:chapter,chapter_title:'Synthetic chapter',
    questions:[{kind:'mc',text:'Choose',options:['A','B'],correct:1,answer_key:'SECRET',parentReview:{note:'PRIVATE'}}]
  }]}});
  const chapters=await api.assignedChapters();
  assert.equal(chapters.length,1);
  assert.equal(chapters[0].questions[0].options.length,2);
  assert.equal(chapters[0].questions[0].correct,undefined);
  assert.ok(!JSON.stringify(chapters).includes('SECRET'));
  assert.ok(!JSON.stringify(chapters).includes('PRIVATE'));
});
test('student feedback stays hidden until server release flag',async()=>{
  const api=client({responses:{cq_v4_my_submission:[{
    chapter_uuid:chapter,submitted_at:'2026-11-13T00:00:00Z',
    feedback_released:false,feedback:'PARENT_ONLY'
  }]}});
  const rows=await api.submission(chapter);
  assert.equal(rows[0].feedback,null);
});
test('missing child token blocks RPC before network request',async()=>{
  const calls=[];
  const api=client({token:'',calls});
  await assert.rejects(()=>api.assignedChapters(),/Student login required/);
  assert.equal(calls.length,0);
});
test('aborted student submission never sends a request',async()=>{
  const calls=[];
  const api=client({calls});
  const controller=new AbortController();controller.abort();
  await assert.rejects(()=>api.submit(chapter,[],{signal:controller.signal}),/취소/);
  assert.equal(calls.length,0);
});
test('malformed submission acknowledgement is not accepted',async()=>{
  const api=client({responses:{cq_v4_submit_answers:[{chapter_uuid:chapter,submitted_at:'not-a-date'}]}});
  await assert.rejects(()=>api.submit(chapter,[]),/제출 확인 응답/);
});
