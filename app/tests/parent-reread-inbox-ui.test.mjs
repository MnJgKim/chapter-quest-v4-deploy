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

test('project change, login reset and logout purge parent inbox state',()=>{
 assert.match(source,/const clearRereadInbox=\(\)=>\{rereadNotices=\[\];rereadOwner=null;rereadAvailable=false;\}/);
 assert.equal(source.split('session=null;clearRereadInbox();issuedInvite=""').length-1,3);
});

test('acknowledgement re-fetch validates all notice records before rendering',()=>{
 const ack=source.indexOf("parentRpc('cq_v4_parent_ack_reread_notice'");
 assert.ok(ack>=0);
 const fragment=source.slice(ack,ack+1100);
 assert.match(fragment,/const valid=rows\.every\(/);
 assert.match(fragment,/if\(!valid\)throw Error\('알림 갱신 데이터가 올바르지 않습니다/);
 assert.match(fragment,/rereadNotices=rows;rereadOwner=owner;rereadAvailable=true;render\(\)/);
});

test('recurring queue remains fail-closed until parent-only atomic bundle status RPC is available',()=>{
 const start=source.indexOf('async function refreshRecurring(){');
 const end=source.indexOf("document.addEventListener('click'",start);
 assert.ok(start>=0&&end>start);
 const fragment=source.slice(start,end);
 assert.match(fragment,/recurringBackendMissing=true/);
 assert.match(fragment,/parentRpc\('cq_v4_parent_recurring_status'\)/);
 assert.match(fragment,/recurringBackendMissing=!Array\.isArray\(capability\)/);
 assert.match(fragment,/catch \(_\) \{ recurringBackendMissing=true; \}/);
 assert.match(source,/if\(willQueue&&recurringBackendMissing\)/);
});
