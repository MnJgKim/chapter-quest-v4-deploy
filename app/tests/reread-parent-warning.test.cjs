'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('app/public/js/parent-app.js','utf8');
const start=src.indexOf('function objectiveReadingAdvisory(row){');
const end=src.indexOf('\n function resultDetails(row){',start);
assert(start>=0&&end>start,'advisory implementation not found');
const advisory=vm.runInNewContext('('+src.slice(start,end).trim()+')');
const qs=Array.from({length:7},(_,i)=>({kind:'mc',text:'Q'+i,options:['Wrong','Right']}));
const row=(correct)=>({lessonContext:{questions:qs,answer_key:Array(7).fill(1)},answers:{answers:Array.from({length:7},(_,i)=>i<correct?1:0)}});
for(let correct=0;correct<=7;correct++){
 const result=advisory(row(correct));
 assert.equal(result.total,7);
 assert.equal(result.needsReread,correct<=4,'70% boundary incorrect for '+correct);
}
assert.equal(advisory({...row(4),lessonContext:null}),null,'missing context must not pass');
assert.equal(advisory({...row(4),lessonContext:{questions:qs,answer_key:[1]}}),null,'key mismatch must not pass');
assert.equal(advisory({...row(4),lessonContext:{questions:qs,answer_key:[1,1,1,1,1,1,null]}}),null,'invalid MC key must not pass');
assert.equal(advisory({...row(4),answers:{answers:[1]}}),null,'answer length mismatch must not pass');
assert(src.includes('재독서 판정 보류'),'unscorable status must be visible');
assert(!src.includes('lessonContext:contexts.get(row.chapter_uuid)||localLessonContext(row.chapter_uuid)'),'stale local fallback must not be used');
console.log('REREAD_ADVISORY_NODE_ASSERTIONS_PASSED');
