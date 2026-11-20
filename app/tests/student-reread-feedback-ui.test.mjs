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
test('student shows authorized reread before feedback release without exposing score',()=>{
 assert.match(app,/if\(submitted\?\.feedback_released&&!rereadProgress&&!rereadStatusUnavailable\)\{\s*try\{rereadSuggested=await viewApi\.releasedRereadSuggestion/);
 assert.match(app,/let rereadSuggested=!!submitted&&!!rereadProgress\?\.required/);
 assert.match(app,/const feedback=submitted\?\.feedback_released\?/);
 const begin=app.indexOf('const rereadNotice=');const end=app.indexOf('const feedback=',begin);
 assert.ok(begin>0&&end>begin);
 assert.doesNotMatch(app.slice(begin,end),/correct_mc|total_mc|answer_key|approval_hash/);
});
test('missing review-only RPC preserves submitted feedback view',()=>{
 assert.match(app,/rereadSuggested=false;\s*console\.warn\('Optional reread suggestion unavailable:/);
 assert.match(app,/assertChildContext\(viewContext\);if\(childApi!==viewApi\)return/);
 assert.match(app,/\$\{feedback\}\$\{rereadStatusNotice\}\$\{rereadNotice\}/);
});

test('token refresh must preserve the same authenticated student identity',()=>{
 assert.match(app,/data\.user\?\.id\|\|data\.user\.id!==owner\.uid/);
 assert.match(app,/if\(session!==owner\|\|generation!==childGeneration\)throw Error\('학생 계정이 변경되었습니다/);
 assert.match(app,/owner\.token=data\.access_token/);
});

test('failed status lookup cannot silently imply reread is unnecessary',()=>{
 assert.match(app,/let rereadStatusUnavailable=false/);
 assert.match(app,/catch\(error\)\{\s*rereadStatusUnavailable=true/);
 assert.match(app,/const rereadStatusNotice=rereadStatusUnavailable\?/);
 assert.match(app,/재독서가 필요하지 않다는 뜻은 아닙니다/);
 assert.match(app,/if\(submitted\?\.feedback_released&&!rereadProgress&&!rereadStatusUnavailable\)/);
});

test('reread completion guards double-click and preserves retry after RPC failure',()=>{
 assert.match(app,/if\(b\.disabled\)return; \/\/ Prevent duplicate requests/);
 assert.match(app,/b\.disabled=true;\s*try\{\s*await api\.completeReread/);
 assert.match(app,/finally\{[\s\S]*?if\(b\.isConnected\)b\.disabled=false/);
 assert.match(app,/const confirmed=await api\.rereadStatus\(c\.chapter_uuid\)/);
 assert.match(app,/if\(!confirmed\?\.required\|\|!confirmed\.completed\)throw Error/);
 assert.match(app,/저장되고 재확인되었습니다/);
});
