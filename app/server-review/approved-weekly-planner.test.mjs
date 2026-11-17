import test from 'node:test';
import assert from 'node:assert/strict';
import {planApprovedWeek} from './approved-weekly-planner.mjs';
const ready=id=>({chapterId:id,approved:true,pdfReady:true,published:true});
const plan=(overrides={})=>planApprovedWeek({student:'서우',monday:'2026-11-23',candidates:[ready('1'),ready('2'),ready('3'),ready('4')],existing:[],...overrides});
test('Seowoo gets Monday Wednesday Thursday; no automatic release',()=>{
 assert.deepEqual(plan().map(({lessonDate,release})=>[lessonDate,release]),[['2026-11-23',false],['2026-11-25',false],['2026-11-26',false]]);
});
test('Seojin and Siwoo have independent configured weekdays',()=>{
 assert.deepEqual(plan({student:'서진'}).map(x=>x.lessonDate),['2026-11-24','2026-11-25','2026-11-27']);
 assert.deepEqual(plan({student:'시우'}).map(x=>x.lessonDate),['2026-11-23','2026-11-24','2026-11-25','2026-11-26']);
});
test('unapproved PDF or unpublished activities never become proposals',()=>{
 const proposals=plan({candidates:[{...ready('a'),approved:false},{...ready('b'),pdfReady:false},{...ready('c'),published:false},ready('d')]});
 assert.deepEqual(proposals.map(x=>x.chapterId),['d']);
});
test('previous unfinished assignment is not assigned twice',()=>{
 const proposals=plan({existing:[{student:'서우',chapterId:'1',lessonDate:'2026-11-16'}]});
 assert.deepEqual(proposals.map(x=>x.chapterId),['2','3','4']);
});
test('manual same-day assignment is preserved and not overwritten',()=>{
 const proposals=plan({existing:[{student:'서우',chapterId:'2',lessonDate:'2026-11-25'}]});
 assert.deepEqual(proposals.map(x=>x.lessonDate),['2026-11-23','2026-11-26']);
 assert.deepEqual(proposals.map(x=>x.chapterId),['1','3']);
});
test('other student assignment cannot consume this students chapter',()=>{
 assert.equal(plan({existing:[{student:'서진',chapterId:'1',lessonDate:'2026-11-24'}]})[0].chapterId,'1');
});
test('input is unchanged and repeat planning is deterministic',()=>{
 const input={student:'서우',monday:'2026-11-23',candidates:[ready('1'),ready('2')],existing:[]};
 const before=JSON.stringify(input);
 assert.deepEqual(planApprovedWeek(input),planApprovedWeek(input));
 assert.equal(JSON.stringify(input),before);
});
test('invalid dates or weekdays are rejected',()=>{
 assert.throws(()=>plan({monday:'2026-02-30'}),/Invalid calendar date/);
 assert.throws(()=>plan({monday:'2026-11-24'}),/Monday/);
 assert.throws(()=>plan({days:[0]}),/weekdays/);
});
