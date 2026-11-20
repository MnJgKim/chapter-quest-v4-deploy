// Offline, non-mutating first-week assignment proposal. Existing lessons are immutable.
const days = Object.freeze({'서우':[1,3,4],'서진':[2,3,5]});
const starts = Object.freeze({'서우':'2026-11-23','서진':'2026-11-24'});
const validDate = s => typeof s==='string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && Number.isFinite(Date.parse(s+'T00:00:00Z')) && new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
export function planFirstWeekAssignments({student,studentUserId,approved,enrolled,chapters,existing=[]}) {
 if (!Object.hasOwn(days,student)||typeof studentUserId!=='string'||!studentUserId||!Array.isArray(chapters)||!Array.isArray(existing)) throw new TypeError('Invalid input');
 const blockers=[];
 if(approved!==true||enrolled!==true) blockers.push('student-not-approved-and-enrolled');
 const ids=new Set();
 for(const c of chapters){
  if(!c||typeof c.chapterId!=='string'||!c.chapterId||ids.has(c.chapterId)) throw new TypeError('Invalid or duplicate catalog');
  ids.add(c.chapterId);
 }
 const used=new Set(),occupied=new Set();
 for(const r of existing){
  if(!r||!validDate(r.lessonDate)||!ids.has(r.chapterId)) throw new TypeError('Invalid existing assignment or incomplete catalog');
  if(used.has(r.chapterId)||occupied.has(r.lessonDate)) blockers.push('existing-assignment-conflict');
  used.add(r.chapterId);occupied.add(r.lessonDate);
 }
 const slots=[];
 for(let d=new Date(starts[student]+'T00:00:00Z');d.toISOString().slice(0,10)<='2026-11-27';d.setUTCDate(d.getUTCDate()+1)){
  if(days[student].includes(d.getUTCDay())) slots.push(d.toISOString().slice(0,10));
 }
 if(existing.some(r=>r.lessonDate>=starts[student] && !days[student].includes(new Date(r.lessonDate+'T00:00:00Z').getUTCDay())))blockers.push('existing-off-day-schedule-requires-review');
 const available=chapters.filter(c=>!used.has(c.chapterId)&&c.pdfReady===true&&c.pdfVerified===true&&c.activityPublished===true);
 const proposals=[];
 for(const date of slots){
  if(occupied.has(date)) continue;
  const chapter=available.shift();
  if(!chapter){blockers.push('insufficient-unassigned-published-chapters');break;}
  proposals.push({student,studentUserId,lessonDate:date,chapterId:chapter.chapterId,timezone:'Asia/Seoul'});
 }
 return {student,slots,proposals:blockers.length===0?proposals:[],existingUnchanged:true,blockers:[...new Set(blockers)],readyForParentReview:blockers.length===0,writesPerformed:0,executable:false};
}
