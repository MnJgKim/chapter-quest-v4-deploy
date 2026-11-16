import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('./public/js/local-app.js',import.meta.url),'utf8');
const coreSource=source.slice(0,source.indexOf("\n'use strict';"));
const context={module:{exports:{}},structuredClone};
vm.runInNewContext(coreSource,context);
const {planWeek}=context.module.exports.CQCore??context.module.exports;
const book={id:'book',students:['서우'],chapters:['1','2','3','4'].map(id=>({id}))};
const assignment=id=>({bookId:'book',chapterId:id});
const state=()=>({books:[book],focus:{},weekly:{},records:{}});
test('new week allocates three distinct chapters in Monday Wednesday Thursday order',()=>{
 const result=planWeek(state(),'서우','2026-11-16');
 assert.deepEqual(['월','수','목'].map(day=>result[day].chapterId),['1','2','3']);
});
test('existing Monday and Thursday assignments remain unchanged when Wednesday is added',()=>{
 const s=state();s.weekly['2026-11-16']={서우:{월:assignment('1'),목:assignment('2')}};
 const result=planWeek(s,'서우','2026-11-16');
 assert.equal(result.월.chapterId,'1');assert.equal(result.목.chapterId,'2');
 assert.equal(result.수.chapterId,'3');
});
test('submitted chapters are excluded from new automatic assignments',()=>{
 const s=state();s.records['서우::book::1']={submitted:true};
 const result=planWeek(s,'서우','2026-11-16');
 assert.deepEqual(['월','수','목'].map(day=>result[day].chapterId),['2','3','4']);
});
test('no book and insufficient remaining chapters return empty slots',()=>{
 const s=state();s.books[0].chapters=[{id:'1'}];
 assert.equal(planWeek(s,'서우','2026-11-16').수,null);
 assert.equal(planWeek(s,'서진','2026-11-16').월,null);
});

test('Seojin gets Tuesday Wednesday Friday by default',()=>{
 const s=state();s.books[0].students.push('서진');
 const result=planWeek(s,'서진','2026-11-16');
 assert.deepEqual(Object.keys(result),['화','수','금']);
 assert.deepEqual(Object.values(result).map(x=>x.chapterId),['1','2','3']);
});
test('Siwoo gets five weekdays by default, with empty slots after available chapters',()=>{
 const s=state();s.books[0].students.push('시우');
 const result=planWeek(s,'시우','2026-11-16');
 assert.deepEqual(Object.keys(result),['월','화','수','목','금']);
 assert.equal(result.금,null);
});
test('parent-configured schedule overrides default days',()=>{
 const s=state();s.schedules={서우:[2,4]};
 const result=planWeek(s,'서우','2026-11-16');
 assert.deepEqual(Object.keys(result),['화','목']);
});
