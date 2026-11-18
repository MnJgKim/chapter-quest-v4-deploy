import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const source=await fs.readFile(new URL('../public/js/student-app.js',import.meta.url),'utf8');
test('completed lesson view retains a PDF viewer but no editable submission form',()=>{
  assert.match(source,/submitted\?\x60<p>제출 완료[^\n]*<div id="cqServerPdfViewer"/);
  assert.match(source,/loadServerPdf\(c\.chapter_uuid,viewUid,viewGeneration\);\s*if\(!submitted\)await restoreDurableVoice/);
  assert.match(source,/if\(!submitted\)\{\s*const activityRows=await viewApi\.chapterActivities/);
  assert.match(source,/if\(!submitted&&c\.lesson_date!==seoulLessonDate\(\)\)/);
});

test('historical PDF viewer stays current without an editable form',()=>{
  assert.match(source,/detail\.dataset\.viewChapter=c\.chapter_uuid/);
  assert.match(source,/document\.getElementById\('cqChildDetail'\)\?\.dataset\.viewChapter===chapterUuid/);
  assert.match(source,/target===document\.getElementById\('cqServerPdfViewer'\)/);
  assert.match(source,/if\(!form\)\{target\.insertAdjacentHTML\('beforeend','<p class="muted">제출 완료 원본 PDF를 읽기 전용으로 표시합니다\.<\/p>'\);return;\}/);
});

test('weekly schedule accepts ISO Seoul lesson dates rather than literal backslash-d',()=>{
  const match=source.match(/lessonSchedule=rows\.filter\(row=>(\/\^.*?\$\/)\.test\(row\.lesson_date/);
  assert.ok(match,'schedule date filter must exist');
  const regex=Function('return '+match[1])();
  assert.equal(regex.test('2026-11-18'),true);
  assert.equal(regex.test('not-a-date'),false);
});

test('weekly lesson button requires server-approved list AND released schedule flag',()=>{
  assert.match(source,/const authorized=chapters\.some\(ch=>ch\.chapter_uuid===c\.chapter_uuid\)/);
  assert.match(source,/available:authorized,is_released:authorized&&c\.is_released===true/);
  assert.match(source,/c\.lesson_date!==todaySeoul\|\|!c\.available\|\|!c\.is_released/);
});

test('review-only weekly schedule release uses approved gate and immutable history, not manual release',async()=>{
  const sql=await fs.readFile(new URL('../../review/sql-candidates/cq_v4_my_lesson_schedule_release_guard.sql',import.meta.url),'utf8');
  assert.match(sql,/cq_v4_can_start_approved_lesson\(s\.chapter_id/);
  assert.match(sql,/cq_v4_student_submissions done/);
  assert.doesNotMatch(sql,/cq_v4_is_released\(/);
  assert.match(sql,/REVIEW CANDIDATE ONLY/);
});

test('speaking upload and recovery sign refresh child JWT instead of using stale session token',()=>{
  assert.match(source,/const uploadToken=await childAccessToken\(\);\s*assertChildContext\(context\)/);
  assert.match(source,/Authorization:'Bearer '\+uploadToken/);
  assert.match(source,/async function verifyExistingAudio[\s\S]*?const token=await childAccessToken\(\)/);
  assert.match(source,/Authorization:'Bearer '\+token,'Content-Type':'application\/json'/);
  assert.doesNotMatch(source,/Authorization:'Bearer '\+session\.token/);
});

test('audio recovery signed URL must target exact student chapter object and contain token',()=>{
  assert.match(source,/const expectedPath='\/storage\/v1\/object\/sign\/cq-v4-speaking\/'\+uid\+'\/'\+uuid\+'\.'\+ext/);
  assert.match(source,/signedUrl\.pathname!==expectedPath\|\|!signedUrl\.searchParams\.has\('token'\)/);
});

test('student login reports weekly schedule RPC failure instead of silently showing empty week',()=>{
  assert.match(source,/let scheduleError=null;/);
  assert.match(source,/fetchStudentLessonSchedule\(\)\.catch\(error=>\{lessonSchedule=\[\];scheduleError=error;\}\)/);
  assert.match(source,/if\(scheduleError\)status\('로그인은 성공했지만 주간 일정 조회에 실패했습니다/);
});

test('student schedule failure is surfaced on all lesson refresh paths',()=>{
  assert.match(source,/async function refreshStudentScheduleNotice\(\)/);
  assert.doesNotMatch(source,/fetchStudentLessonSchedule\(\)\.catch\(\(\)=>\{lessonSchedule=\[\];\}\)/);
  assert.ok((source.match(/await refreshStudentScheduleNotice\(\)/g)||[]).length>=4);
  assert.match(source,/let scheduleNotice=null;\s*try\{const rows=await api\.assignedChapters\(\)/);
});

test('student PDF edge signed URL must match the authorized original object and token',async()=>{
  const edge=await fs.readFile(new URL('../supabase/functions/cq-v4-pdf-link/index.ts',import.meta.url),'utf8');
  assert.match(edge,/const expectedSignedPath='\/storage\/v1\/object\/sign\/cq-v4-originals\/'\+chapterRow\.storage_path/);
  assert.match(edge,/signed\.pathname!==expectedSignedPath\|\|!signed\.searchParams\.has\('token'\)/);
  assert.match(edge,/userClient\.rpc\('cq_v4_can_read_lesson'/);
  assert.match(edge,/createSignedUrl\(chapterRow\.storage_path,120\)/);
});
