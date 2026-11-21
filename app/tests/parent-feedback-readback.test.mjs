import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/js/parent-app.js',import.meta.url),'utf8');

test('parent feedback save distinguishes committed RPC from failed readback',()=>{
 const start=source.indexOf("}else if(button.dataset.parentFeedback==='save'){");
 const end=source.indexOf("\n   }catch(error){parentStatus(",start);
 assert.ok(start>=0&&end>start,'feedback save handler must exist');
 const handler=source.slice(start,end);
 const write=handler.indexOf("await parentRpc('cq_v4_release_feedback'");
 const read=handler.indexOf("await parentRpc('cq_v4_parent_submissions'");
 assert.ok(write>=0&&read>write,'readback must follow committed save');
 assert.match(handler,/try\{\s*const rows=await parentRpc\('cq_v4_parent_submissions'\)/);
 assert.match(handler,/catch\(refreshError\)\{[\s\S]*?피드백 저장은 성공했지만 재조회에 실패했습니다/);
 assert.match(handler,/if\(!Array\.isArray\(rows\)\)throw Error/);
});
