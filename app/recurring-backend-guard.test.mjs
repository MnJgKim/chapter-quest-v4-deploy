import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Script} from 'node:vm';

const source=readFileSync(new URL('./public/js/parent-app.js',import.meta.url),'utf8');

test('parent app browser script parses',()=>{
  assert.doesNotThrow(()=>new Script(source,{filename:'parent-app.js'}));
});

test('recurring queue fails closed until server capability is confirmed',()=>{
  assert.match(source,/recurringBackendMissing=true/);
  assert.doesNotMatch(source,/recurringBackendMissing=false/);
  assert.match(source,/if\(willQueue&&recurringBackendMissing\)/);
  assert.match(source,/자동 공개 대기열 서버 기능 확인 전에는 등록할 수 없습니다/);
});

test('recurring panel reads existing scheduled releases without fabricating queue records',()=>{
  assert.match(source,/parentRpc\('cq_v4_parent_list_lesson_releases'\)/);
  assert.match(source,/if\(!Array\.isArray\(rows\)\)throw Error\('서버 일정 응답 오류'\)/);
  assert.match(source,/recurringRows=rows\.filter\(r=>r\.lesson_date\)/);
  assert.match(source,/recurringOwner=owner;render\(\)/);
  assert.match(source,/parentRpc\('cq_v4_parent_recurring_status'\)/);
});

test('recurring controls stay closed unless the server capability probe succeeds',()=>{
  assert.match(source,/recurringBackendMissing=!Array\.isArray\(capability\)/);
  assert.match(source,/catch \(_\) \{ recurringBackendMissing=true; \}/);
  assert.match(source,/if\(owner!==cloudIdentity\(\)\)return/);
  assert.match(source,/catch\(error\)\{const statusNode=document\.getElementById\('cqRecurringStatus'\)/);
});
