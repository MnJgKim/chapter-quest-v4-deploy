/* V4 TEST only add-only assignment validation; no server writes. */
(function(root){
 'use strict';
 const TEST_UID='7169dd67-99d7-4b86-85f8-bafce01e51b7';
 function validate({chapter,studentId,students,children,assignments}){
  if(!chapter?.ready||typeof chapter.uuid!=='string'||!chapter.uuid)throw Error('검증된 PDF가 필요합니다.');
  if(studentId!==TEST_UID)throw Error('V4 TEST 계정만 배정할 수 있습니다.');
  if(!Array.isArray(students)||!students.some(s=>s.student_user_id===TEST_UID))throw Error('서버 학생 목록에 테스트 계정이 없습니다.');
  if(!Array.isArray(children)||!children.some(c=>c.child_user_id===TEST_UID&&c.active===true))throw Error('활성 연결된 테스트 계정이 아닙니다.');
  if(!Array.isArray(assignments))throw Error('기존 배정 목록을 확인할 수 없습니다.');
  if(assignments.some(a=>a.chapter_uuid===chapter.uuid&&a.student_user_id===TEST_UID))throw Error('이미 배정된 챕터입니다.');
  return {chapter_uuid:chapter.uuid,student_user_id:TEST_UID};
 }
 root.CQTestAssignmentGuard=Object.freeze({TEST_UID,validate});
})(globalThis);
