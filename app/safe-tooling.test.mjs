import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
test('development wrapper rejects live deployment commands before starting Wrangler',()=>{
 const result=spawnSync(process.execPath,[new URL('./tools/run-wrangler.mjs',import.meta.url).pathname,'deploy'],{encoding:'utf8'});
 assert.equal(result.status,2);assert.match(result.stderr,/deployment is not supported/);
});
