/* Pure planning only. Never writes to Supabase or releases student content.
 * Caller must authorize the parent/student relationship and validate approved
 * content server-side before committing a proposed assignment.
 */
export const DEFAULT_STUDENT_DAYS=Object.freeze({
 '서우':[1,3,4], '서진':[2,3,5], '시우':[1,2,3,4,5]
});
function isoDate(date){
 if(typeof date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(date))throw Error('Invalid ISO date');
 const d=new Date(date+'T00:00:00Z');
 if(!Number.isFinite(d.valueOf())||d.toISOString().slice(0,10)!==date)throw Error('Invalid calendar date');
 return d;
}
function addDays(date,n){const d=isoDate(date);d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);}
function eligible(c){
 return c?.approved===true&&c?.pdfReady===true&&c?.published===true
   &&typeof c.chapterId==='string'&&c.chapterId.length>0;
}
/** monday: ISO date of Monday in Asia/Seoul calendar.
 * existing: all prior and future dated assignments for this student;
 * candidates: ordered chapters, already filtered to this student's authorized books.
 * Does NOT generate released_at, grant access, or alter input objects.
 */
export function planApprovedWeek({student,monday,days,candidates=[],existing=[]}){
 const start=isoDate(monday);
 if(start.getUTCDay()!==1)throw Error('Week must start Monday');
 if(typeof student!=='string'||!student.trim())throw Error('Student required');
 const configured=days??DEFAULT_STUDENT_DAYS[student]??[];
 if(!Array.isArray(configured)||configured.some(n=>!Number.isInteger(n)||n<1||n>7))throw Error('Invalid weekdays');
 if(!Array.isArray(existing)||!Array.isArray(candidates))throw Error('Invalid inputs');
 const studentAssignments=existing.filter(a=>a?.student===student);
 const used=new Set(studentAssignments.map(a=>a.chapterId));
 const dates=[...new Set(configured)].sort((a,b)=>a-b).map(day=>addDays(monday,day-1));
 const occupied=new Set(studentAssignments.map(a=>a.lessonDate));
 const proposed=[];
 for(const lessonDate of dates){
  if(occupied.has(lessonDate))continue;
  const next=candidates.find(c=>eligible(c)&&!used.has(c.chapterId));
  if(!next)continue;
  proposed.push({student,chapterId:next.chapterId,lessonDate,release:false});
  used.add(next.chapterId);
 }
 return proposed;
}
