// Read-only reconciliation. Never edits published or historical lessons.
const weekdays = Object.freeze({'서우':[1,3,4],'서진':[2,3,5]});
const validDate = s => typeof s==='string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s+'T00:00:00Z')) && new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
export function reconcileStudentSchedule({student,firstDate,existing,chapters}) {
 if(!Object.hasOwn(weekdays,student)) throw new TypeError('Unknown student');
 if(!validDate(firstDate)||!Array.isArray(existing)||!Array.isArray(chapters)) throw new TypeError('Invalid input');
 const conflicts=[],reservedDates=new Set(),reservedChapters=new Set();
 for(const r of existing){
  if(!r||!validDate(r.lessonDate)||typeof r.chapterId!=='string'||!r.chapterId) throw new TypeError('Invalid existing row');
  if(reservedDates.has(r.lessonDate)||reservedChapters.has(r.chapterId)) conflicts.push('duplicate-existing-assignment');
  reservedDates.add(r.lessonDate);reservedChapters.add(r.chapterId);
  if(r.lessonDate>=firstDate && !weekdays[student].includes(new Date(r.lessonDate+'T00:00:00Z').getUTCDay())) conflicts.push('off-day-existing-assignment');
 }
 if(chapters.some(c=>typeof c!=='string'||!c)||new Set(chapters).size!==chapters.length) throw new TypeError('Invalid chapter catalog');
 if(existing.some(r=>!chapters.includes(r.chapterId))) conflicts.push('incomplete-chapter-catalog');
 const publishedExisting=existing.filter(r=>r.released===true);
 if(publishedExisting.some(r=>r.lessonDate>=firstDate)) conflicts.push('published-future-assignment-preserve');
 const firstLesson=existing.filter(r=>r.lessonDate===firstDate);
 if(firstLesson.length===0) conflicts.push('first-lesson-unassigned');
 return {student,firstDate,existingCount:existing.length,firstLessonCount:firstLesson.length,
  conflicts:[...new Set(conflicts)],requiresManualReview:conflicts.length>0,
  proposedChanges:[],writesPerformed:0,productionSafeToApply:false};
}
