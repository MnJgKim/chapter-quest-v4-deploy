import {spawnSync} from 'node:child_process';import {mkdir,writeFile} from 'node:fs/promises';import pg from 'pg';
import {SafeError,needed,root,isMain,runCli,databaseOptions,validateTarget} from './common.mjs';import {apply,assertInstalled} from './apply.mjs';import {probe} from './probe.mjs';
export async function localRun(env=process.env){
 const binary=needed(env,'CQ_TEST_SUPABASE_CLI'),workdir=needed(env,'CQ_LOCAL_SUPABASE_WORKDIR');
 const child=spawnSync(binary,['status','--workdir',workdir,'--output','json'],{env,encoding:'utf8',maxBuffer:1024*1024});if(child.status!==0)throw new SafeError('LOCAL_SUPABASE_NOT_READY');
 let info;try{info=JSON.parse(child.stdout);}catch{throw new SafeError('LOCAL_STATUS_NOT_JSON');}
 const api=new URL(info.API_URL),dbUrl=new URL(info.DB_URL);
 const target={kind:'local',purpose:'disposable-test',confirmedDisposable:true,projectRef:'chapter-quest-integration-local',supabaseUrl:api.origin,databaseHost:dbUrl.hostname,appOrigin:'http://127.0.0.1:8787',workerOrigin:'http://127.0.0.1:8787'};
 const localEnv={...env,CQ_TEST_CONFIRMED_PROJECT_REF:target.projectRef,CQ_TEST_SUPABASE_ANON_KEY:info.ANON_KEY,CQ_TEST_SERVICE_ROLE_KEY:info.SERVICE_ROLE_KEY,CQ_TEST_DATABASE_URL:info.DB_URL};
 validateTarget(target,localEnv);if(!info.ANON_KEY||!info.SERVICE_ROLE_KEY)throw new SafeError('LOCAL_KEYS_MISSING');
 const folder=new URL('.integration/',root);await mkdir(folder,{recursive:true,mode:0o700});const file=new URL('local-target.json',folder);await writeFile(file,JSON.stringify(target,null,2),{mode:0o600});localEnv.CQ_TEST_TARGET_FILE=file.pathname;
 const db=new pg.Client(databaseOptions(target,localEnv));await db.connect();let installed;try{installed=(await db.query("select to_regnamespace('cq_private') as app")).rows[0].app;if(installed)await assertInstalled(db,target);}finally{await db.end();}
 if(!installed)await apply(localEnv);return probe(localEnv);
}
if(isMain(import.meta.url))await runCli(async()=>{if(!process.argv.includes('--run'))throw new SafeError('EXPLICIT_LOCAL_RUN_FLAG_REQUIRED');await localRun();});
