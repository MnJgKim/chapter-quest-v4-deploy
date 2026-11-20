/* Add-only assignment validation for approved active children; no server writes. */
(function(root){
 'use strict';
 function validate({chapter,studentId,students,children,assignments}){
  if(!chapter?.ready||typeof chapter.uuid!=='string'||!chapter.uuid)throw Error('검증된 PDF가 필요합니다.');
  if(typeof studentId!=='string'||!studentId)throw Error('배정할 학생을 선택하세요.');
  if(!Array.isArray(students)||!students.some(s=>s.student_user_id===studentId))throw Error('서버 학생 목록에 해당 계정이 없습니다.');
  if(!Array.isArray(children)||!children.some(c=>c.child_user_id===studentId&&c.active===true))throw Error('승인된 활성 연결 학생이 아닙니다.');
  if(!Array.isArray(assignments))throw Error('기존 배정 목록을 확인할 수 없습니다.');
  if(assignments.some(a=>a.chapter_uuid===chapter.uuid&&a.student_user_id===studentId))throw Error('이미 배정된 챕터입니다.');
  return {chapter_uuid:chapter.uuid,student_user_id:studentId};
 }
 root.CQTestAssignmentGuard=Object.freeze({validate});
})(globalThis);
