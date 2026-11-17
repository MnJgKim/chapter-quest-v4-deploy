/* Server-side orchestration contract for an eventual atomic database RPC.
 * This module never calls Supabase directly and cannot substitute for an
 * authenticated transaction. The writer MUST implement all-or-nothing
 * authorization, approval rechecks, student locking and date collision checks.
 */
import {previewApprovedWeek} from './approved-weekly-preview.mjs';
import {preflightSchedule} from './schedule-preflight.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function prepareWeeklyCommit({parentUserId,studentUserId,student,monday,days,readScope}){
 const proposed=await previewApprovedWeek({parentUserId,studentUserId,student,monday,days,readScope});
 const scope=await readScope({parentUserId,studentUserId});
 if(!scope||scope.parentUserId!==parentUserId||scope.studentUserId!==studentUserId||scope.parentAuthorized!==true||scope.studentEnrolled!==true||!Array.isArray(scope.assignments))throw Error('Server scope changed');
 return preflightSchedule({parentUserId,studentUserId,proposals:proposed,existing:scope.assignments});
}
export async function commitWeeklyAtomically({parentUserId,studentUserId,proposals,atomicWriter}){
 if(!UUID.test(parentUserId||'')||!UUID.test(studentUserId||'')||typeof atomicWriter!=='function')throw Error('Trusted atomic writer required');
 const safe=preflightSchedule({parentUserId,studentUserId,proposals,existing:[]});
 if(!safe.length)return {inserted:0,skipped:true};
 // Never split this into separate per-chapter RPC calls.
 // The writer is responsible for fresh DB checks and transactional locks.
 return atomicWriter({parentUserId,studentUserId,proposals:safe});
}
