/* Adapter for a trusted, parent-scoped database query.
 * It cannot authorize students, verify approval signatures or perform writes.
 * The server MUST re-check ownership, enrollment, approval and publication
 * atomically before inserting a schedule row.
 */
import {planApprovedWeek} from './approved-weekly-planner.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH=/^[a-f0-9]{64}$/i;
function uuid(v){return typeof v==='string'&&UUID.test(v);}
function date(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v))return false;const d=new Date(v+'T00:00:00Z');return Number.isFinite(d.valueOf())&&d.toISOString().slice(0,10)===v;}
/** Rows must originate from a parent-authorized, student-scoped server query.
 * A local boolean or a published_at timestamp alone is NOT approval evidence.
 */
export function proposeFromScopedRows({student,studentUserId,parentUserId,monday,days,chapters,assignments}){
 if(!uuid(studentUserId)||!uuid(parentUserId)||!Array.isArray(chapters)||!Array.isArray(assignments))throw Error('Trusted parent/student scope required');
 // Duplicate or conflicting chapter records must never silently decide authorization.
 const seen=new Set();
 if(chapters.some(row=>{if(!uuid(row?.chapter_id))return false;const key=row.chapter_id;if(seen.has(key))return true;seen.add(key);return false;}))throw Error('Duplicate chapter evidence');
 const candidates=chapters.filter(row=>
   row?.parent_user_id===parentUserId&&row?.student_user_id===studentUserId
   &&uuid(row.chapter_id)&&row.pdf_ready===true
   &&typeof row.pdf_verified_at==='string'&&Number.isFinite(Date.parse(row.pdf_verified_at))
   &&typeof row.published_at==='string'&&Number.isFinite(Date.parse(row.published_at))
   &&uuid(row.approval_id)&&typeof row.approval_hash==='string'&&HASH.test(row.approval_hash)
   &&row.approval_verified===true
 ).map(row=>({chapterId:row.chapter_id,approved:true,pdfReady:true,published:true}));
 // Fail closed if a caller supplies an assignment for another parent/student.
 if(assignments.some(a=>a?.parent_user_id!==parentUserId||a?.student_user_id!==studentUserId||!uuid(a.chapter_id)||!date(a.lesson_date)))throw Error('Assignment scope mismatch');
 const existing=assignments.map(a=>({student,chapterId:a.chapter_id,lessonDate:a.lesson_date}));
 return planApprovedWeek({student,monday,days,candidates,existing}).map(row=>({
   parent_user_id:parentUserId,student_user_id:studentUserId,chapter_id:row.chapterId,
   lesson_date:row.lessonDate,release:false
 }));
}
