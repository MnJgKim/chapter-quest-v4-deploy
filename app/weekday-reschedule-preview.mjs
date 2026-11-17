// Preview-only rescheduling of unpublished, future lessons. NEVER executes writes.
// Intended for explicit parent review after backup and rollback validation.
const days={'서우':[1,3,4],'서진':[2,3,5]};
const start={'서우':'2026-11-23','서진':'2026-11-24'};
const iso=d=>d.toISOString().slice(0,10);
const parse=s=>{if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(s))throw new TypeError('Invalid date');const d=new Date(s+'T00:00:00Z');if(!Number.isFinite(+d)||iso(d)!==s)throw new TypeError('Invalid date');return d;};
export function previewWeekdayReschedule({student,existing,throughDate,asOfDate='2026-11-17'}){
 if(!Object.hasOwn(days,student)||!Array.isArray(existing))throw new TypeError('Invalid input');
 const from=parse(start[student]),through=parse(throughDate),asOf=parse(asOfDate);
 if(through<from||(+through-+from)/86400000>366)throw new RangeError('Invalid horizon');
 const sorted=existing.map(r=>{if(!r||typeof r.chapterId!=='string'||!r.chapterId)throw new TypeError('Invalid row');parse(r.lessonDate);return {...r};}).sort((a,b)=>a.lessonDate.localeCompare(b.lessonDate));
 if(new Set(sorted.map(r=>r.chapterId)).size!==sorted.length||new Set(sorted.map(r=>r.lessonDate)).size!==sorted.length)throw new Error('Conflicting existing assignments');
 const blockers=[];
 if(sorted.some(r=>r.lessonDate<=iso(asOf)))blockers.push('historical-lessons-require-separate-preservation');
 if(sorted.some(r=>r.submitted===true))blockers.push('submitted-lesson-cannot-move');
 if(sorted.some(r=>r.released===true))blockers.push('published-lesson-requires-separate-approval');
 const slots=[];
 for(let t=+from;t<=+through;t+=86400000){const d=new Date(t);if(days[student].includes(d.getUTCDay()))slots.push(iso(d));}
 if(slots.length<sorted.length)blockers.push('insufficient-weekday-slots');
 const changes=sorted.map((r,i)=>({chapterId:r.chapterId,fromDate:r.lessonDate,toDate:slots[i]??null,changed:r.lessonDate!==slots[i]}));
 return {student,changes,blockers,writesPerformed:0,executable:false,requiresBackupAndFinalApproval:true};
}
