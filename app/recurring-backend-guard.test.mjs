import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Script} from 'node:vm';

const source=readFileSync(new URL('./public/js/parent-app.js',import.meta.url),'utf8');

test('parent app browser script parses',()=>{
  assert.doesNotThrow(()=>new Script(source,{filename:'parent-app.js'}));
});

test('recurring queue fails closed before server capability check',()=>{
  assert.match(source,/recurringBackendMissing=true/);
  assert.match(source,/recurringBackendMissing\?'disabled title=/);
  assert.match(source,/recurringBackendMissing\?'disabled':/);
  assert.match(source,/if\(willQueue&&recurringBackendMissing\)/);
});

test('missing status RPC is explicitly reported, without simulated queue rows',()=>{
  assert.match(source,/parentRpc\('cq_v4_parent_recurring_status'\)/);
  assert.match(source,/PGRST202/i);
  assert.match(source,/recurringRows=\[\];recurringOwner=owner/);
  assert.match(source,/자동 공개 대기열 서버 기능이 아직 설치되지 않았습니다/);
});

test('successful status response alone unlocks controls; unrelated errors propagate',()=>{
  assert.match(source,/recurringBackendMissing=false/);
  assert.match(source,/if\(!Array\.isArray\(rows\)\)throw Error/);
  assert.match(source,/throw error;/);
});
