import test from 'node:test';import assert from 'node:assert/strict';import {recurringLessonDates as dates} from './recurring-weekdays.mjs';
test('Seowoo first week Mon Wed Thu',()=>assert.deepEqual(dates({student:'서우',throughDate:'2026-11-27'}).dates,['2026-11-23','2026-11-25','2026-11-26']));
test('Seojin first week Tue Wed Fri',()=>assert.deepEqual(dates({student:'서진',throughDate:'2026-11-27'}).dates,['2026-11-24','2026-11-25','2026-11-27']));
test('recurs into second week',()=>assert.deepEqual(dates({student:'서우',throughDate:'2026-12-04'}).dates,['2026-11-23','2026-11-25','2026-11-26','2026-11-30','2026-12-02','2026-12-03']));
test('honors later start',()=>assert.deepEqual(dates({student:'서진',fromDate:'2026-12-01',throughDate:'2026-12-04'}).dates,['2026-12-01','2026-12-02','2026-12-04']));
test('rejects invalid date',()=>assert.throws(()=>dates({student:'서우',throughDate:'2026-11-31'}),/Invalid date/));
test('rejects before first class',()=>assert.throws(()=>dates({student:'서우',fromDate:'2026-11-20',throughDate:'2026-11-30'}),/range/));
test('rejects unbounded horizon',()=>assert.throws(()=>dates({student:'서우',throughDate:'2028-01-01'}),/range/));
test('never mutates',()=>{const r=dates({student:'서진',throughDate:'2026-11-27'});assert.equal(r.writesPerformed,0);assert.equal(r.executable,false)});
