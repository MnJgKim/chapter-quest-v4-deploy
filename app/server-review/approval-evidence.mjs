/* Build a verified, parent-scoped approval view from database records.
 * Do not trust approval_verified flags sent by the browser.
 * This function does not perform authorization or database writes:
 * server must scope all rows to the authenticated parent and enrolled student.
 */
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH=/^[0-9a-f]{64}$/i;
export function verifyChapterApproval({parentUserId,studentUserId,chapters,approvals}){
 if(!UUID.test(parentUserId||'')||!UUID.test(studentUserId||'')||!Array.isArray(chapters)||!Array.isArray(approvals))throw Error('Trusted scope required');
 return chapters.map(c=>{
  const matches=approvals.filter(a=>
   a?.parent_user_id===parentUserId&&a?.chapter_uuid===c?.chapter_id
   &&a?.id===c?.approval_id&&typeof a?.content_hash==='string'
   &&HASH.test(a.content_hash)&&a.content_hash===c?.approval_hash
  );
  return {...c,approval_verified:
   c?.parent_user_id===parentUserId&&c?.student_user_id===studentUserId
   &&matches.length===1};
 });
}
