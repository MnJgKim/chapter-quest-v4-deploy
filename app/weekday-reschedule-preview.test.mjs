import test from 'node:test';import assert from 'node:assert/strict';import {previewWeekdayReschedule as preview} from './weekday-reschedule-preview.mjs';
const existing=[{chapterId:'1',lessonDate:'2026-11-23'},{chapterId:'2',lessonDate:'2026-11-26'},{chapterId:'3',lessonDate:'2026-11-30'}];
const run=(o={})=>preview({student:'서우',existing,throughDate:'2026-12-31',...o});
test('reorders to Mon Wed Thu without reusing chapters',()=>{const r=run();assert.deepEqual(r.changes.map(c=>c.toDate),['2026-11-23','2026-11-25','2026-11-26']);assert.equal(r.writesPerformed,0);assert.equal(r.executable,false)});
test('published future lessons are flagged for separate approval',()=>assert.ok(run({existing:[{...existing[0],released:true}]}).blockers.includes('published-lesson-requires-separate-approval')));
test('submitted lessons cannot move',()=>assert.ok(run({existing:[{...existing[0],submitted:true}]}).blockers.includes('submitted-lesson-cannot-move')));
test('past lessons require preservation',()=>assert.ok(run({asOfDate:'2026-11-24'}).blockers.includes('historical-lessons-require-separate-preservation')));
test('not enough weekday slots blocks',()=>assert.ok(run({throughDate:'2026-11-23'}).blockers.includes('insufficient-weekday-slots')));
test('duplicate chapter is refused',()=>assert.throws(()=>run({existing:[existing[0],{...existing[1],chapterId:'1'}]}),/Conflicting/));
test('Seojin starts Tue Wed Fri',()=>assert.deepEqual(preview({student:'서진',existing:[{chapterId:'1',lessonDate:'2026-11-24'},{chapterId:'2',lessonDate:'2026-11-27'}],throughDate:'2026-11-30'}).changes.map(c=>c.toDate),['2026-11-24','2026-11-25']));

test('released date change explicitly requires rollback review',()=>{const r=run({existing:[existing[0],{...existing[1],released:true}]});assert.ok(r.blockers.includes('released-lesson-date-change-requires-rollback-review'));assert.equal(r.readyForParentReview,false)});
