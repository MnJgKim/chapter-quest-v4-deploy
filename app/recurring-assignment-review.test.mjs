import test from 'node:test';import assert from 'node:assert/strict';import {reviewRecurringAssignments as review} from './recurring-assignment-review.mjs';
const chapters=Array.from({length:10},(_,i)=>({chapterId:'ch-'+i,pdfReady:true,pdfVerified:true,activityPublished:true}));
const args={student:'서진',studentUserId:'student',approved:true,enrolled:true,chapters,existing:[],throughDate:'2026-11-27'};
test('Seojin first week proposes three published chapters',()=>{const r=review(args);assert.deepEqual(r.proposals.map(x=>x.lessonDate),['2026-11-24','2026-11-25','2026-11-27']);assert.equal(r.readyForParentReview,true);assert.equal(r.executable,false)});
test('existing first lesson stays unchanged',()=>{const r=review({...args,existing:[{chapterId:'ch-0',lessonDate:'2026-11-24'}]});assert.deepEqual(r.proposals.map(x=>x.chapterId),['ch-1','ch-2'])});
test('insufficient catalog never yields partial plan',()=>{const r=review({...args,chapters:chapters.slice(0,1)});assert.equal(r.proposals.length,0);assert.ok(r.blockers.includes('insufficient-verified-unassigned-chapters'))});
test('unapproved student yields no plan',()=>assert.deepEqual(review({...args,approved:false}).proposals,[]));
test('unpublished activity excluded',()=>assert.deepEqual(review({...args,chapters:chapters.map(c=>({...c,activityPublished:false}))}).proposals,[]));
test('existing off day blocks plan',()=>{const r=review({...args,existing:[{chapterId:'ch-0',lessonDate:'2026-11-26'}]});assert.deepEqual(r.proposals,[]);assert.ok(r.blockers.includes('existing-date-outside-target-schedule'))});
test('duplicate snapshot blocks plan',()=>assert.deepEqual(review({...args,existing:[{chapterId:'ch-0',lessonDate:'2026-11-24'},{chapterId:'ch-1',lessonDate:'2026-11-24'}]}).proposals,[]));
test('snapshot must be explicit',()=>assert.throws(()=>review({...args,existing:undefined}),/Complete snapshot/));

test('future lessons outside review horizon are not treated as off-day conflicts',()=>{const r=review({...args,existing:[{chapterId:'ch-9',lessonDate:'2026-12-20'}]});assert.equal(r.readyForParentReview,true);assert.equal(r.proposals.length,3)});
test('released existing lesson off-day requires separate approval',()=>{const r=review({...args,existing:[{chapterId:'ch-0',lessonDate:'2026-11-26',released:true}]});assert.ok(r.blockers.includes('released-existing-lesson-requires-separate-approval'));assert.deepEqual(r.proposals,[])});
