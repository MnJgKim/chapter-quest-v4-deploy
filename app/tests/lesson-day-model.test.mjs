// Pure authorization model tests; NOT PostgreSQL/RLS/Edge integration tests.
import test from 'node:test';
import assert from 'node:assert/strict';
const seoulDay=(iso)=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(iso));
const canStart=({caller,student,day,lesson,submitted,assigned,released,published})=>caller===student&&!submitted&&assigned&&released&&published&&day===lesson;
const canRead=(x)=>canStart(x)||(x.caller===x.student&&x.submitted&&x.assigned&&x.published);
test('Seoul boundary 23:59 -> 00:00',()=>{assert.equal(seoulDay('2026-11-22T14:59:00Z'),'2026-11-22');assert.equal(seoulDay('2026-11-22T15:00:00Z'),'2026-11-23')});
const x={caller:'student-A',student:'student-A',day:'2026-11-23',lesson:'2026-11-23',submitted:false,assigned:true,released:true,published:true};
test('current day allowed',()=>assert.equal(canStart(x),true));
test('future denied',()=>assert.equal(canStart({...x,lesson:'2026-11-24'}),false));
test('past incomplete denied',()=>assert.equal(canStart({...x,lesson:'2026-11-22'}),false));
test('completed history read-only',()=>{assert.equal(canStart({...x,submitted:true}),false);assert.equal(canRead({...x,submitted:true,lesson:'2026-11-22'}),true)});
test('cross student denied',()=>assert.equal(canRead({...x,caller:'student-B',submitted:true}),false));
test('not released denied',()=>assert.equal(canStart({...x,released:false}),false));
test('unassigned denied',()=>assert.equal(canStart({...x,assigned:false}),false));
