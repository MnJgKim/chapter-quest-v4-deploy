// Local development/build only. Neither entrypoint can deploy the application.
import {createRequire} from 'node:module';
import {mkdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const mode=process.argv[2];
if(!['build','dev'].includes(mode)){console.error('Use build or dev; deployment is not supported.');process.exit(2);}
const root=fileURLToPath(new URL('../../',import.meta.url));
const require=createRequire(import.meta.url);
const cli=path.join(path.dirname(require.resolve('wrangler/package.json')),'bin/wrangler.js');
const config=process.env.XDG_CONFIG_HOME||path.join(root,'.local-tools','config');
await mkdir(config,{recursive:true});
const args=mode==='build'?['deploy','--config',path.join(root,'wrangler.jsonc'),'--dry-run','--outdir',path.join(root,'app/.build')]:['dev','--config',path.join(root,'wrangler.jsonc'),'--local'];
const child=spawn(process.execPath,[cli,...args],{cwd:root,stdio:'inherit',env:{...process.env,XDG_CONFIG_HOME:config,WRANGLER_SEND_METRICS:'false'}});
child.once('error',()=>{console.error('Local Wrangler could not start.');process.exitCode=1;});
child.once('exit',(code)=>{process.exitCode=code??1;});
