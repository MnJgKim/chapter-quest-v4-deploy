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
