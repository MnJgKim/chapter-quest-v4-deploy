// Pure preflight. Identity must be established from approved invite, never from a date.
const first = Object.freeze({'서우':'2026-11-23','서진':'2026-11-24'});
const days = Object.freeze({'서우':[1,3,4],'서진':[2,3,5]});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function evaluateFirstLesson({student,identity,lessons}) {
 if (!Object.hasOwn(first,student) || !Array.isArray(lessons)) throw new TypeError('Invalid student or lessons');
 const blockers=[];
 if (!identity || identity.approved!==true || !uuid.test(identity.studentUserId||'') || identity.name!==student) blockers.push('approved-identity-unverified');
 if (identity && identity.enrolled!==true) blockers.push('enrollment-unverified');
 const matches=lessons.filter(r=>r.lessonDate===first[student]);
 if(matches.length!==1) blockers.push(matches.length?'duplicate-first-lesson':'first-lesson-missing');
 const row=matches.length===1?matches[0]:null;
 if(row){
  if(!identity || row.studentUserId!==identity.studentUserId) blockers.push('student-ownership-mismatch');
  if(!uuid.test(row.chapterId||'')) blockers.push('chapter-id-invalid');
  if(row.pdfReady!==true || row.pdfVerified!==true) blockers.push('pdf-unverified');
  if(row.activityPublished!==true) blockers.push('activity-unpublished');
  if(row.assigned!==true) blockers.push('assignment-unverified');
  if(row.released!==true) blockers.push('release-unverified');
 }
 for(const r of lessons){
  if(typeof r.lessonDate!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(r.lessonDate)||!Number.isFinite(Date.parse(r.lessonDate+'T00:00:00Z'))) throw new TypeError('Invalid lesson date');
  if(r.lessonDate>=first[student]&&!days[student].includes(new Date(r.lessonDate+'T00:00:00Z').getUTCDay())) blockers.push('off-day-existing');
 }
 return {student,firstLessonDate:first[student],blockers:[...new Set(blockers)],dataPrerequisitesMet:blockers.length===0,studentLoginVerified:false,deviceVerified:false,liveReady:false,writesPerformed:0};
}
