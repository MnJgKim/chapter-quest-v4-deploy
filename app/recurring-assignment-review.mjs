import {recurringLessonDates} from './recurring-weekdays.mjs';
// Review-only bridge from verified catalog and complete schedule snapshot to recurring dates.
// All-or-nothing; no DB calls, mutations or publication.
export function reviewRecurringAssignments({student,studentUserId,approved,enrolled,chapters,existing,throughDate,fromDate}){
 if(!Array.isArray(existing)||!Array.isArray(chapters)||typeof studentUserId!=='string'||!studentUserId)throw new TypeError('Complete snapshot, catalog and student required');
 const dates=recurringLessonDates({student,throughDate,fromDate}).dates;
 const blockers=[];
 if(approved!==true||enrolled!==true)blockers.push('student-not-approved-and-enrolled');
 const ids=new Set();
 for(const c of chapters){if(!c||typeof c.chapterId!=='string'||!c.chapterId||ids.has(c.chapterId))throw new TypeError('Invalid or duplicate catalog');ids.add(c.chapterId)}
 const occupied=new Set(),used=new Set();
 for(const r of existing){
  if(!r||!ids.has(r.chapterId)||typeof r.lessonDate!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(r.lessonDate)||Number.isNaN(Date.parse(r.lessonDate+'T00:00:00Z'))||new Date(r.lessonDate+'T00:00:00Z').toISOString().slice(0,10)!==r.lessonDate)throw new TypeError('Invalid existing assignment or incomplete catalog');
  if(used.has(r.chapterId)||occupied.has(r.lessonDate))blockers.push('existing-assignment-conflict');
  used.add(r.chapterId);occupied.add(r.lessonDate);
  if(r.lessonDate>=(fromDate??(student==='서우'?'2026-11-23':'2026-11-24'))&&r.lessonDate<=throughDate&&!dates.includes(r.lessonDate))blockers.push('existing-date-outside-target-schedule');
 }
 if(existing.some(r=>r.released===true&&r.lessonDate>=dates[0]&&!dates.includes(r.lessonDate)))blockers.push('released-existing-lesson-requires-separate-approval');
 const available=chapters.filter(c=>!used.has(c.chapterId)&&c.pdfReady===true&&c.pdfVerified===true&&c.activityPublished===true);
 const proposals=[];
 for(const date of dates){if(occupied.has(date))continue;const c=available.shift();if(!c){blockers.push('insufficient-verified-unassigned-chapters');break}proposals.push({student,studentUserId,lessonDate:date,chapterId:c.chapterId,timezone:'Asia/Seoul'})}
 return {student,dates,proposals:blockers.length?[]:proposals,blockers:[...new Set(blockers)],readyForParentReview:blockers.length===0,writesPerformed:0,executable:false};
}
