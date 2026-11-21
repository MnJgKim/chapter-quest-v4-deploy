import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/js/parent-app.js',import.meta.url),'utf8');
test('successful reread acknowledgement survives failed inbox readback',()=>{
 const start=source.indexOf("}else if(b.dataset.parentReread==='ack'){");
 const end=source.indexOf("\n  }catch(error){",start);
 assert.ok(start>=0&&end>start,'acknowledgement handler exists');
 const handler=source.slice(start,end);
 const write=handler.indexOf("await parentRpc('cq_v4_parent_ack_reread_notice'");
 const read=handler.indexOf("await parentRpc('cq_v4_parent_reread_inbox'");
 assert.ok(write>=0&&read>write);
 assert.match(handler,/if\(acknowledged!==true\)throw Error/);
 assert.match(handler,/existing\.acknowledged_at=new Date\(\)\.toISOString\(\)/);
 assert.match(handler,/catch\(refreshError\)\{[\s\S]*?알림 확인은 성공했지만 재조회에 실패했습니다/);
 assert.doesNotMatch(handler,/rereadNotices=\[\]/);
});
