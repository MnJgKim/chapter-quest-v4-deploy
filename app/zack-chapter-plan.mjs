// Pure planning only. Never writes schedules, PDFs, approvals, or submissions.
export function planSharedZackChapter(input) {
  const { chapterUuid, pdfVerified, approved, published, parentReviewed, students } = input ?? {};
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuid.test(chapterUuid ?? '')) throw new Error('A real, existing chapter UUID is required');
  if (pdfVerified !== true || approved !== true || published !== true || parentReviewed !== true) {
    throw new Error('Verified PDF, genuine parent review, approval, and publication are required');
  }
  if (!Array.isArray(students) || students.length !== 2) throw new Error('Two separate student assignments required');
  const seen = new Set();
  const assignments = students.map(({studentUuid, lessonDate}) => {
    if (!uuid.test(studentUuid ?? '') || seen.has(studentUuid)) throw new Error('Invalid or duplicate student');
    seen.add(studentUuid);
    if (typeof lessonDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(lessonDate) || Number.isNaN(Date.parse(`${lessonDate}T00:00:00Z`)) || new Date(`${lessonDate}T00:00:00Z`).toISOString().slice(0,10) !== lessonDate) throw new Error('Invalid lesson date');
    return Object.freeze({studentUuid, chapterUuid, lessonDate, timezone:'Asia/Seoul'});
  });
  return Object.freeze({chapterUuid, assignments:Object.freeze(assignments), requiresProductionApproval:true, writesPerformed:0});
}
