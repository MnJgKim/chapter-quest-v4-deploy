import {spawnSync} from 'node:child_process';import {readdir} from 'node:fs/promises';
for(const name of await readdir(new URL('.',import.meta.url))){if(!name.endsWith('.mjs'))continue;const result=spawnSync(process.execPath,['--check',new URL(name,import.meta.url).pathname],{stdio:'inherit'});if(result.status!==0)process.exit(result.status||1);}
console.log('PASS integration script syntax');
