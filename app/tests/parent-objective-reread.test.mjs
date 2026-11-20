import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
const source=await fs.readFile(new URL('../public/js/parent-app.js',import.meta.url),'utf8');
const match=source.match(/ function objectiveReadingAdvisory\(row\)\{[\s\S]*?\n \}/);
assert.ok(match,'parent-only objective grading helper missing');
const objectiveReadingAdvisory=vm.runInNewContext('('+match[0].trim()+')');
const make=(key,answers,kind='mc')=>({lessonContext:{questions:key.map(()=>({kind,options:['a','b','c']})),answer_key:key},answers:{answers}});
test('below 70% of verified MC answers shows reread advisory',()=>{
 const r=objectiveReadingAdvisory(make([0,1,2,0,1,2,0,1,2,0],['0','1','2','0','1','2','1','0','0','2']));
 assert.equal(r.correct,6);assert.equal(r.total,10);assert.equal(r.needsReread,true);
});
test('exact 70% does not show reread warning',()=>{
 const r=objectiveReadingAdvisory(make([0,0,0,0,0,0,0,0,0,0],['0','0','0','0','0','0','0','1','1','1']));
 assert.equal(r.correct,7);assert.equal(r.needsReread,false);
});
test('missing or malformed answer key fails closed',()=>{
 assert.equal(objectiveReadingAdvisory(make([0,1],['0'])),null);
 assert.equal(objectiveReadingAdvisory(make([0,5],['0','1'])),null);
 assert.equal(objectiveReadingAdvisory(make([0,1],['0','invalid'])),null);
 assert.equal(objectiveReadingAdvisory(make([0,1],['0','1'],'short')),null);
});
test('parent alert is advisory only and not student feedback or notification delivery',()=>{
 assert.match(source,/재독서 권장 · 부모 확인 필요/);
 assert.match(source,/학생에게 자동 전송되지 않습니다/);
 assert.match(source,/const rereadNotice=advisory\?\.needsReread/);
});

test('mixed subjective and objective work scores only MC answers',()=>{
 const row={lessonContext:{questions:[{kind:'mc',options:['A','B']},{kind:'short'},{kind:'mc',options:['A','B']}],answer_key:[1,'sample',0]},answers:{answers:['1','a thoughtful essay','1']}};
 const score=objectiveReadingAdvisory(row);
 assert.equal(score.total,2);assert.equal(score.correct,1);assert.equal(score.needsReread,true);
});
test('zero MC, missing key and malformed answers do not invent scores',()=>{
 const row={lessonContext:{questions:[{kind:'short'}],answer_key:['sample']},answers:{answers:['essay']}};
 assert.equal(objectiveReadingAdvisory(row),null);
 assert.equal(objectiveReadingAdvisory({lessonContext:{questions:[{kind:'mc',options:['A','B']}]},answers:{answers:['0']}}),null);
 assert.equal(objectiveReadingAdvisory({lessonContext:{questions:[{kind:'mc',options:['A','B']}],answer_key:[0]},answers:{answers:['1.0']}}),null);
});
