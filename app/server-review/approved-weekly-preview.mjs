/* Server-only read-only preview. Not an HTTP handler and never a writer.
 * readScope must enforce parent authentication, admin authorization, enrollment
 * and return complete, student-scoped rows from the same trusted snapshot.
 */
import {verifyChapterApproval} from './approval-evidence.mjs';
import {proposeFromScopedRows} from './approved-weekly-adapter.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function previewApprovedWeek({parentUserId,studentUserId,student,monday,days,readScope}){
 if(!UUID.test(parentUserId||'')||!UUID.test(studentUserId||'')||typeof readScope!=='function')throw Error('Authorized server reader required');
 const scope=await readScope({parentUserId,studentUserId});
 if(!scope||scope.parentUserId!==parentUserId||scope.studentUserId!==studentUserId
   ||scope.parentAuthorized!==true||scope.studentEnrolled!==true
   ||!Array.isArray(scope.chapters)||!Array.isArray(scope.approvals)
   ||!Array.isArray(scope.assignments))throw Error('Unauthorized or incomplete server scope');
 const verified=verifyChapterApproval({parentUserId,studentUserId,chapters:scope.chapters,approvals:scope.approvals});
 return proposeFromScopedRows({parentUserId,studentUserId,student,monday,days,chapters:verified,assignments:scope.assignments});
}
