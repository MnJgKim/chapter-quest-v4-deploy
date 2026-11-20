import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const edge=readFileSync(new URL('../review/edge-candidates/cq-v4-pdf-link/index.ts',import.meta.url),'utf8');
const schedule=readFileSync(new URL('../review/sql-candidates/cq_v4_my_lesson_schedule_release_guard.sql',import.meta.url),'utf8');

test('student PDF candidate checks authoritative release before signing',()=>{
  const auth=edge.indexOf('const userId=userData.user?.id');
  const release=edge.indexOf("userClient.rpc('cq_v4_is_released'");
  const sign=edge.indexOf("createSignedUrl(chapterRow.storage_path,120)");
  assert.ok(auth>=0&&release>auth&&sign>release);
  assert.match(edge,/p_chapter:chapter,p_student:userId/);
  assert.match(edge,/if\(releaseError\)return json\(\{error:'LESSON_RELEASE_CHECK_FAILED'\},503\)/);
  assert.match(edge,/if\(released!==true\)return json\(\{error:'LESSON_NOT_RELEASED'\},403\)/);
  assert.doesNotMatch(edge,/\.upload\(|\.remove\(/);
});
test('schedule candidate uses same release predicate without changing output columns',()=>{
  assert.match(schedule,/RETURNS TABLE\(chapter_uuid uuid, chapter_title text, lesson_date date, is_released boolean\)/);
  // New work uses the approved lesson gate; only immutable prior submissions remain visible.
  assert.match(schedule,/public\.cq_v4_can_start_approved_lesson\(s\.chapter_id, \(select auth\.uid\(\)\)\)/);
  assert.match(schedule,/OR EXISTS \(SELECT 1 FROM public\.cq_v4_student_submissions done/);
  assert.match(schedule,/done\.child_user_id=\(select auth\.uid\(\)\)/);
  assert.match(schedule,/done\.chapter_uuid=s\.chapter_id/);
  assert.match(schedule,/s\.student_user_id=\(select auth\.uid\(\)\)/);
  assert.match(schedule,/ORDER BY s\.lesson_date, s\.chapter_id/);
  assert.doesNotMatch(schedule,/\b(?:DELETE|TRUNCATE|DROP)\b/i);
});

const localEdge=readFileSync(new URL('./local-supabase/supabase/functions/cq-v4-pdf-link/index.ts',import.meta.url),'utf8');

test('local integration Edge retains PDF integrity checks and enforces release before signing',()=>{
  const release=localEdge.indexOf("userClient.rpc('cq_v4_is_released'");
  const sign=localEdge.indexOf("createSignedUrl(chapterRow.storage_path,120)");
  assert.ok(release>=0&&release<sign);
  assert.match(localEdge,/if\(released!==true\)return json\(\{error:'LESSON_NOT_RELEASED'\},403\)/);
  assert.match(localEdge,/APPROVED_RANGE_REQUIRED/);
  assert.match(localEdge,/DERIVED_PDF_INTEGRITY_FAILED/);
  assert.match(localEdge,/page_count:pageCount/);
});
