// Pure, offline-only schedule proposal. NEVER writes to hosted Supabase.
const WEEKDAYS = Object.freeze({ '서우': [1,3,4], '서진': [2,3,5] });
const iso = d => d.toISOString().slice(0,10);
function dateUTC(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new TypeError('Expected YYYY-MM-DD');
  const d = new Date(`${s}T00:00:00Z`);
  if (!Number.isFinite(d.valueOf()) || iso(d) !== s) throw new TypeError('Invalid calendar date');
  return d;
}
export function proposeHostedLessons({ student, startDate, endDate, chapters, existing = [] }) {
  if (!Object.hasOwn(WEEKDAYS, student)) throw new TypeError('Unknown student; no inferred identity');
  const start = dateUTC(startDate), end = dateUTC(endDate);
  if (start > end || (end-start)/86400000 > 366) throw new RangeError('Invalid schedule range');
  if (!Array.isArray(chapters) || !Array.isArray(existing)) throw new TypeError('Expected arrays');
  if (chapters.some(c => typeof c !== 'string' || !c.trim()) || new Set(chapters).size !== chapters.length) throw new TypeError('Invalid chapter identifiers');
  if (existing.some(e => !e || typeof e.chapterId !== 'string' || typeof e.lessonDate !== 'string')) throw new TypeError('Invalid existing assignments');
  for (const e of existing) dateUTC(e.lessonDate);
  if (existing.some(e => !chapters.includes(e.chapterId))) throw new Error('Existing assignment chapter missing from supplied catalog; review required');
  if (new Set(existing.map(e => e.chapterId)).size !== existing.length ||
      new Set(existing.map(e => e.lessonDate)).size !== existing.length) {
    throw new Error('Conflicting existing assignments; preserve records and request review');
  }
  const usedChapters = new Set(existing.map(e => e.chapterId));
  const usedDates = new Set(existing.map(e => e.lessonDate));
  const remaining = chapters.filter(id => !usedChapters.has(id));
  const proposed = [];
  for (let time = start.getTime(); time <= end.getTime(); time += 86400000) {
    const day = new Date(time);
    const date = iso(day);
    if (!WEEKDAYS[student].includes(day.getUTCDay()) || usedDates.has(date)) continue;
    const chapterId = remaining.shift();
    if (!chapterId) break;
    proposed.push({ student, lessonDate: date, chapterId, timezone: 'Asia/Seoul' });
  }
  return { proposed, existingUnchanged: true, writesPerformed: 0, requiresParentApproval: true, readyForAutomaticHostedRelease: false };
}
