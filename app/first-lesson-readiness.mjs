// Pure, read-only first-lesson readiness gate; no student identity inference or network.
const FIRST = Object.freeze({'서우':'2026-11-23','서진':'2026-11-24'});
export function checkFirstLessonReadiness({student,lessonDate,assigned,pdfReady,activityPublished,releasedAt,chapterId,studentApproved,studentEnrolled}) {
  if (!Object.hasOwn(FIRST,student)) throw new TypeError('Unknown student');
  const failures=[];
  if(lessonDate!==FIRST[student]) failures.push('first-lesson-date');
  if(typeof chapterId!=='string'||!chapterId.trim()) failures.push('chapter-id');
  if(assigned!==true) failures.push('assignment');
  if(pdfReady!==true) failures.push('original-pdf');
  if(activityPublished!==true) failures.push('published-questions');
  if(studentApproved!==true) failures.push('parent-approval');
  if(studentEnrolled!==true) failures.push('student-enrollment');
  if(typeof releasedAt!=='string'||!Number.isFinite(Date.parse(releasedAt))) failures.push('release-approval');
  return {student,firstLessonDate:FIRST[student],prerequisitesSatisfied:failures.length===0,failures,
    hostedReleaseVerified:false,studentLoginVerified:false,deviceVerified:false,readyForLiveLesson:false,
    writesPerformed:0};
}
