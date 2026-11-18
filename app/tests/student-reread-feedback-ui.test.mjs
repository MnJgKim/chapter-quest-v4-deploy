import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const app=readFileSync(new URL('../public/js/student-app.js',import.meta.url),'utf8');
const api=readFileSync(new URL('../public/js/student-api.js',import.meta.url),'utf8');
test('reread suggestion RPC returns strict Boolean and validates chapter UUID',()=>{
 assert.match(api,/async function releasedRereadSuggestion\(chapterUuid,options=\{\}\)/);
 assert.match(api,/p_chapter:requireChapterUuid\(chapterUuid\)/);
 assert.match(api,/typeof value!=='boolean'/);
});
test('student only asks for reread after released feedback and does not expose score',()=>{
 assert.match(app,/if\(submitted\?\.feedback_released\)\{\s*try\{rereadSuggested=await viewApi\.releasedRereadSuggestion/);
 assert.match(app,/submitted\?\.feedback_released&&rereadSuggested/);
 const begin=app.indexOf('const rereadNotice=');const end=app.indexOf('const feedback=',begin);
 assert.ok(begin>0&&end>begin);
 assert.doesNotMatch(app.slice(begin,end),/correct_mc|total_mc|answer_key|approval_hash/);
});
test('missing review-only RPC preserves submitted feedback view',()=>{
 assert.match(app,/rereadSuggested=false;\s*console\.warn\('Optional reread suggestion unavailable:/);
 assert.match(app,/assertChildContext\(viewContext\);if\(childApi!==viewApi\)return/);
 assert.match(app,/\$\{feedback\}\$\{rereadNotice\}/);
});

test('token refresh must preserve the same authenticated student identity',()=>{
 assert.match(app,/data\.user\?\.id\|\|data\.user\.id!==owner\.uid/);
 assert.match(app,/if\(session!==owner\|\|generation!==childGeneration\)throw Error\('학생 계정이 변경되었습니다/);
 assert.match(app,/owner\.token=data\.access_token/);
});
