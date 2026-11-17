// Build an explicit parent-reviewed RPC plan from an offline schedule proposal.
// NO network, credentials, database writes, or automatic publication.
export function buildParentRpcPlan({proposed, studentUserIds, parentApproved = false}) {
  if (!Array.isArray(proposed) || !studentUserIds || typeof studentUserIds !== 'object') throw new TypeError('Invalid proposal');
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const seen = new Set();
  const calls = proposed.map(row => {
    if (!row || !['서우','서진'].includes(row.student) ||
        !uuid.test(row.chapterId || '') || !uuid.test(studentUserIds[row.student] || '') ||
        !/^\d{4}-\d{2}-\d{2}$/.test(row.lessonDate || '') ||
        new Date(row.lessonDate+'T00:00:00Z').toISOString().slice(0,10) !== row.lessonDate) throw new TypeError('Invalid hosted assignment');
    const key = row.student+'::'+row.lessonDate;
    if (seen.has(key)) throw new Error('Duplicate student lesson date');
    seen.add(key);
    return {rpc:'cq_v4_parent_schedule_lesson',args:{p_student_user_id:studentUserIds[row.student],p_chapter_id:row.chapterId,p_lesson_date:row.lessonDate}};
  });
  return {calls, executable:false, parentApproved:parentApproved === true, writesPerformed:0,
    // A separate authenticated and authorized workflow must verify live enrollment,
    // PDF, published activity and existing assignments before invoking these RPCs.
    releaseCalls:[],requiresLivePreflight:true,requiresFinalDeploymentApproval:true};
}
