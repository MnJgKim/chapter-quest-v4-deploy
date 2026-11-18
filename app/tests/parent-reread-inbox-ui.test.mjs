import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/js/parent-app.js',import.meta.url),'utf8');
test('parent inbox is opt-in and does not automatically create or sync notices',()=>{
 assert.match(source,/data-parent-reread="refresh"/);
 assert.match(source,/parentRpc\('cq_v4_parent_reread_inbox'\)/);
 assert.match(source,/parentRpc\('cq_v4_parent_ack_reread_notice'/);
 assert.doesNotMatch(source,/parentRpc\('cq_v4_parent_sync_reread_notice'/);
});
test('parent inbox handles missing RPC and account switches without leaking old notices',()=>{
 assert.match(source,/rereadOwner===cloudIdentity\(\)/);
 assert.match(source,/if\(cloudIdentity\(\)!==owner\)return/);
 assert.match(source,/rereadNotices=\[\];rereadOwner=null;rereadAvailable=false/);
 assert.match(source,/서버 알림 RPC가 설치되지 않아 알림함이 비활성화되었습니다/);
});
test('inbox never renders server answer key or student answer JSON',()=>{
 const start=source.indexOf('const rereadPanel=');const end=source.indexOf('const feedbackPanel=',start);
 assert.ok(start>=0&&end>start);
 const panel=source.slice(start,end);
 assert.doesNotMatch(panel,/answer_key|\.answers|approval_hash/);
 assert.match(panel,/acknowledged_at/);
});
