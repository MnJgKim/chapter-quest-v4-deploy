// Runs entirely in a temporary synthetic repository. Never touches Cloudflare or production.
import {mkdtemp,mkdir,writeFile,readFile,rm,copyFile,unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const source=fileURLToPath(new URL('./asset-integrity-audit.mjs',import.meta.url));
const dir=await mkdtemp(join(tmpdir(),'cq-asset-integrity-'));
const run=(...args)=>spawnSync(process.execPath,[join(dir,'app/tools/asset-integrity-audit.mjs'),...args],{encoding:'utf8'});
try{
 await mkdir(join(dir,'app/tools'),{recursive:true});
 await mkdir(join(dir,'app/public/js'),{recursive:true});
 await copyFile(source,join(dir,'app/tools/asset-integrity-audit.mjs'));
 await writeFile(join(dir,'app/public/js/parent-app.js'),'baseline');
 await writeFile(join(dir,'app/worker.mjs'),'worker');
 await writeFile(join(dir,'wrangler.jsonc'),'{}');
 let initial=run();
 assert.equal(initial.status,0,initial.stderr);
 const manifest=JSON.parse(initial.stdout);
 assert.equal(manifest.scope,'repository-candidate-not-live-cloudflare');
 assert.equal(manifest.files.length,3);
 assert.ok(manifest.files.every(f=>/^[a-f0-9]{64}$/.test(f.sha256)&&Number.isInteger(f.size)));
 const baseline=join(dir,'baseline.json');
 await writeFile(baseline,initial.stdout);
 let same=run('--baseline',baseline);
 assert.equal(same.status,0,same.stderr);
 assert.deepEqual(JSON.parse(same.stderr).baselineComparison,{changed:[],added:[],removed:[]});
 await writeFile(join(dir,'app/public/js/parent-app.js'),'tampered');
 let changed=run('--baseline',baseline);
 assert.equal(changed.status,1);
 assert.deepEqual(JSON.parse(changed.stderr).baselineComparison.changed,['app/public/js/parent-app.js']);
 await writeFile(join(dir,'app/public/js/parent-app.js'),'baseline');
 await writeFile(join(dir,'app/public/js/extra.js'),'added');
 let added=run('--baseline',baseline);
 assert.equal(added.status,1);
 assert.deepEqual(JSON.parse(added.stderr).baselineComparison.added,['app/public/js/extra.js']);
 await unlink(join(dir,'app/public/js/extra.js'));
 await unlink(join(dir,'app/public/js/parent-app.js'));
 let removed=run('--baseline',baseline);
 assert.equal(removed.status,1);
 assert.deepEqual(JSON.parse(removed.stderr).baselineComparison.removed,['app/public/js/parent-app.js']);
 await writeFile(join(dir,'app/public/js/parent-app.js'),'baseline');
 await writeFile(baseline,JSON.stringify({...manifest,files:[manifest.files[0],manifest.files[0]]}));
 let duplicate=run('--baseline',baseline);
 assert.notEqual(duplicate.status,0);
 console.log('ASSET_INTEGRITY_ISOLATED_ASSERTIONS_PASSED');
}finally{await rm(dir,{recursive:true,force:true});}
