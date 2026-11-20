// Deployment preflight only. Never deploys or changes Cloudflare resources.
// Usage: node app/tools/deploy-preflight.mjs --target stage|production
import {readFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const root=fileURLToPath(new URL('../../',import.meta.url));
const args=process.argv.slice(2);
if(args.length!==2||args[0]!=='--target'||!['stage','production'].includes(args[1])){
  console.error('Usage: node app/tools/deploy-preflight.mjs --target stage|production (dry-run only)');
  process.exit(2);
}
const target=args[1];
const config=JSON.parse((await readFile(join(root,'wrangler.jsonc'),'utf8')).replace(/^\s*\/\/.*$/gm,''));
if(config.name!=='chapter-quest-v4'||config.main!=='app/worker.mjs'||config.assets?.directory!=='./app/public'){
  throw Error('Unexpected Wrangler config: refusing preflight');
}
config.name=target==='stage'?'chapter-quest-v4-stage':'chapter-quest-v4';
// Temporary config lives outside the repo: resolve asset and entrypoint paths explicitly.
config.main=join(root,'app/worker.mjs');
config.assets.directory=join(root,'app/public');
const dir=await mkdtemp(join(tmpdir(),'cq-v4-preflight-'));
try{
  const configPath=join(dir,'wrangler.json');
  await writeFile(configPath,JSON.stringify(config,null,2));
  const require=createRequire(import.meta.url);
  const cli=join(require.resolve('wrangler/package.json'),'..');
  const cliPath=resolve(cli,'bin/wrangler.js');
  // Explicitly dry-run; no Cloudflare credentials or network needed.
  const run=spawnSync(process.execPath,[cliPath,'deploy','--config',configPath,'--dry-run','--outdir',join(dir,'build')],{
    cwd:root,stdio:'inherit',env:{...process.env,WRANGLER_SEND_METRICS:'false'}
  });
  if(run.error)throw run.error;
  if(run.status!==0)process.exitCode=run.status||1;
  else console.log('Dry-run passed for '+config.name+'. No deployment performed.');
}finally{
  await rm(dir,{recursive:true,force:true});
}
