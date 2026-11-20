import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('../public/js/student-app.js',import.meta.url),'utf8');
const start=source.indexOf('function seoulLessonDate(){');
const end=source.indexOf('\n  function draw()',start);
assert.ok(start>=0&&end>start,'Student screen must define Seoul lesson date');
const fn=source.slice(start,end);

test('student release date uses Seoul calendar day across UTC midnight',()=>{
 const cases=[
  ['2026-11-22T14:59:59Z','2026-11-22'],
  ['2026-11-22T15:00:00Z','2026-11-23'],
  ['2026-11-23T14:59:59Z','2026-11-23'],
  ['2026-11-23T15:00:00Z','2026-11-24']
 ];
 for(const [instant,expected] of cases){
  const RealDate=Date;
  class FixedDate extends RealDate {constructor(...args){super(...(args.length?args:[instant]));}}
  const context=vm.createContext({Intl,Date:FixedDate});
  const result=vm.runInContext(fn+'\nseoulLessonDate()',context);
  assert.equal(result,expected,instant);
 }
});
