import test from 'node:test';import assert from 'node:assert/strict';import './public/js/student-api.js';
const uuid='11111111-1111-4111-8111-111111111111';
const client=rows=>globalThis.CQStudentAPI.createStudentAPI({url:'https://test.supabase.co',anonKey:'test',getAccessToken:async()=>'student',fetchImpl:async()=>Response.json(rows)});
test('student transport returns only public question fields',async()=>{const rows=await client([{chapter_uuid:uuid,chapter_title:'Chapter',answer_key:[0],questions:[{kind:'mc',text:'Who?',options:['A','B'],correct:0,sample:'secret'}]}]).assignedChapters();assert.deepEqual(rows[0].questions,[{kind:'mc',text:'Who?',options:['A','B']}]);assert.equal(rows[0].answer_key,undefined);});
test('malformed question options fail with a clear error before rendering',async()=>assert.rejects(client([{chapter_uuid:uuid,questions:[{kind:'mc',text:'Who?',options:{a:'A'}}]}]).assignedChapters(),/선택지/));
test('missing question array cannot produce a blank learning form',async()=>assert.rejects(client([{chapter_uuid:uuid,questions:null}]).assignedChapters(),/학습 자료/));
