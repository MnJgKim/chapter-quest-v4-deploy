import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql', import.meta.url), 'utf8');

test('student RPC exposes only the server clock and authenticated identity', () => {
  assert.match(sql, /v_student uuid := \(SELECT auth\.uid\(\)\)/);
  assert.match(sql, /cq_v4_ensure_approved_lesson_at\(pg_catalog\.statement_timestamp\(\)\)/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.cq_v4_ensure_approved_lesson_at\(timestamptz\)\s+FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.cq_v4_ensure_today_approved_lesson\(\) TO authenticated/);
});

test('automatic writes are limited to the release of an existing slot or a new schedule slot', () => {
  assert.doesNotMatch(sql, /\b(?:DELETE|TRUNCATE|DROP)\b/i);
  assert.match(sql, /UPDATE public\.cq_v4_lesson_schedule s\s+SET released_at = p_now/);
  assert.match(sql, /ON CONFLICT \(student_user_id, chapter_id\) DO NOTHING/);
  assert.doesNotMatch(
    sql,
    /\b(?:INSERT INTO|UPDATE)\s+public\.cq_v4_(?:pdf_assignments|student_submissions|activities|approved_chapter_queue|pdf_chapters)\b/i
  );
});
