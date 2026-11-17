export const TEST_UID='7169dd67-99d7-4b86-85f8-bafce01e51b7';
export function validateTestAssignment({chapter,studentId,students,children,assignments}) {
 if(!chapter?.ready||typeof chapter.uuid!=='string')throw Error('verified PDF required');
 if(studentId!==TEST_UID)throw Error('test account only');
 if(!Array.isArray(students)||!students.some(s=>s.student_user_id===TEST_UID))throw Error('student not in server list');
 if(!Array.isArray(children)||!children.some(c=>c.child_user_id===TEST_UID&&c.active===true))throw Error('test account not linked');
 if(!Array.isArray(assignments)||assignments.some(a=>a.chapter_uuid===chapter.uuid&&a.student_user_id===TEST_UID))throw Error('already assigned');
 return Object.freeze({chapter_uuid:chapter.uuid,student_user_id:TEST_UID});
}
