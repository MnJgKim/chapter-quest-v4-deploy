/* Preflight for an eventual atomic server-side schedule transaction.
 * Read-only. A successful preflight NEVER authorizes a database write.
 * The database transaction must recheck authorization, enrollment, approval,
 * published content, existing dates and uniqueness under a student lock.
 */
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE=/^\d{4}-\d{2}-\d{2}$/;
const validDate=s=>typeof s==='string'&&DATE.test(s)&&!Number.isNaN(Date.parse(s+'T00:00:00Z'))&&new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
export function preflightSchedule({parentUserId,studentUserId,proposals,existing}){
 if(!UUID.test(parentUserId||'')||!UUID.test(studentUserId||'')||!Array.isArray(proposals)||!Array.isArray(existing))throw Error('Invalid server scope');
 const occupied=new Set(),chapters=new Set();
 for(const row of existing){
  if(row?.parent_user_id!==parentUserId||row?.student_user_id!==studentUserId||!UUID.test(row.chapter_id||'')||!validDate(row.lesson_date))throw Error('Invalid existing scope');
  occupied.add(row.lesson_date);chapters.add(row.chapter_id);
 }
 const proposedDates=new Set(),proposedChapters=new Set();
 for(const row of proposals){
  if(row?.parent_user_id!==parentUserId||row?.student_user_id!==studentUserId||!UUID.test(row.chapter_id||'')||!validDate(row.lesson_date)||row.release!==false)throw Error('Invalid or released proposal');
  if(occupied.has(row.lesson_date)||chapters.has(row.chapter_id)||proposedDates.has(row.lesson_date)||proposedChapters.has(row.chapter_id))throw Error('Schedule collision');
  proposedDates.add(row.lesson_date);proposedChapters.add(row.chapter_id);
 }
 return proposals.map(row=>({...row}));
}
