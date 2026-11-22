// Read-only deployment inventory. No network, Cloudflare calls, or deployment.
// Usage: node app/tools/asset-integrity-audit.mjs [--baseline path/to/manifest.json]
import {readFile,readdir,lstat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,relative,join,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const assetRoot=resolve(root,'app/public');
const args=process.argv.slice(2);
if(args.length!==0 && !(args.length===2&&args[0]==='--baseline'))throw Error('Usage: node app/tools/asset-integrity-audit.mjs [--baseline manifest.json]');
const hex=bytes=>createHash('sha256').update(bytes).digest('hex');
const manifest={schema:1,scope:'repository-candidate-not-live-cloudflare',files:[]};
async function visit(dir){
 for(const entry of (await readdir(dir,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name,'en'))){
  const path=join(dir,entry.name);
  const stat=await lstat(path);
  if(stat.isSymbolicLink())throw Error('Symlink refused: '+relative(root,path));
  if(stat.isDirectory()){await visit(path);continue;}
  if(!stat.isFile())throw Error('Non-regular file refused: '+relative(root,path));
  const bytes=await readFile(path);
  manifest.files.push({path:relative(root,path).split(sep).join('/'),size:bytes.length,sha256:hex(bytes)});
 }
}
await visit(assetRoot);
for(const name of ['app/worker.mjs','wrangler.jsonc']){
 const bytes=await readFile(resolve(root,name));
 manifest.files.push({path:name,size:bytes.length,sha256:hex(bytes)});
}
manifest.files.sort((a,b)=>a.path.localeCompare(b.path,'en'));
const seen=new Set();
for(const f of manifest.files){
 if(seen.has(f.path))throw Error('Duplicate path '+f.path);
 seen.add(f.path);
}
if(args.length){
 const baseline=JSON.parse(await readFile(resolve(args[1]),'utf8'));
 if(baseline.schema!==1||!Array.isArray(baseline.files))throw Error('Invalid baseline manifest');
 const old=new Map();
 for(const f of baseline.files){
  if(typeof f.path!=='string'||typeof f.sha256!=='string'||old.has(f.path))throw Error('Invalid baseline entry');
  old.set(f.path,f);
 }
 const current=new Map(manifest.files.map(f=>[f.path,f]));
 const changed=manifest.files.filter(f=>old.has(f.path)&&old.get(f.path).sha256!==f.sha256).map(f=>f.path);
 const added=manifest.files.filter(f=>!old.has(f.path)).map(f=>f.path);
 const removed=[...old.keys()].filter(p=>!current.has(p)).sort();
 console.error(JSON.stringify({baselineComparison:{changed,added,removed}},null,2));
 if(changed.length||added.length||removed.length)process.exitCode=1;
}
process.stdout.write(JSON.stringify(manifest,null,2)+'\n');
