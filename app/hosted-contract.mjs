// Offline-only hosted contract checker. Never connects to Supabase or Cloudflare.
export const REQUIRED = Object.freeze({
  tables: ['cq_v4_pdf_chapters','cq_v4_pdf_assignments','cq_v4_pdf_enrollments','cq_v4_activities','cq_v4_lesson_schedule'],
  functions: ['cq_v4_is_released','cq_v4_my_released_chapters','cq_v4_submit_answers','cq_is_admin'],
  buckets: ['cq-v4-originals','cq-v4-speaking']
});
const norm = value => value.trim().toLowerCase();
export function auditHostedInventory(snapshot) {
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) throw new TypeError('Invalid inventory');
  const missing = {};
  for (const [type, required] of Object.entries(REQUIRED)) {
    const values = snapshot[type];
    if (!Array.isArray(values) || values.some(value => typeof value !== 'string' || !value.trim())) throw new TypeError(`Invalid ${type}`);
    const actual = new Set(values.map(norm));
    missing[type] = required.filter(value => !actual.has(norm(value)));
  }
  return {objectsPresent: Object.values(missing).every(values => values.length === 0), missing,
    rlsVerified: false, grantsVerified: false, signaturesVerified: false, storagePoliciesVerified: false,
    hostedReady: false, safeToDeploy: false};
}
export function auditStudentSchedule(schedule) {
  if (!Array.isArray(schedule)) throw new TypeError('Schedule must be an array');
  const required = {'서우':[1,3,4],'서진':[2,3,5]};
  const errors = [];
  for (const [student, days] of Object.entries(required)) {
    const actual = schedule.find(row => row.student === student)?.days;
    if (!Array.isArray(actual) || actual.some(day => !Number.isInteger(day) || day < 0 || day > 6) ||
      new Set(actual).size !== actual.length || days.some(day => !actual.includes(day)) || actual.length !== days.length) {
      errors.push(`${student}: expected weekdays ${days.join(',')}`);
    }
  }
  return {valid: errors.length === 0, errors, appliesToHostedAssignments: false};
}