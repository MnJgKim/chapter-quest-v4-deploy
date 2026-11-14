import {spawn} from 'node:child_process';import {loadTarget,needed,isMain,runCli,SafeError,fileURLToPath,root} from './common.mjs';
export async function deployFunctions(env=process.env){
 const target=await loadTarget(env);if(target.kind!=='hosted')throw new SafeError('HOSTED_TEST_TARGET_REQUIRED');needed(env,'SUPABASE_ACCESS_TOKEN');const binary=needed(env,'CQ_TEST_SUPABASE_CLI');
 const invoke=async args=>{
  const code=await new Promise((resolve,reject)=>{const child=spawn(binary,args,{env,stdio:['ignore','ignore','ignore']});child.once('error',()=>reject(new SafeError('SUPABASE_CLI_START_FAILED')));child.once('close',resolve);});
  if(code!==0)throw new SafeError('TEST_EDGE_CLI_FAILED');
 };
 await invoke(['secrets','set','APP_ORIGIN='+target.appOrigin,'--project-ref',target.projectRef,'--workdir',fileURLToPath(root)]);
 console.log('CONFIGURED test Edge APP_ORIGIN');
 for(const name of ['cq-v4-student-account','cq-v4-pdf-parent','cq-v4-pdf-link']){
  await invoke(['functions','deploy',name,'--use-api','--project-ref',target.projectRef,'--workdir',fileURLToPath(root)]);
  console.log('DEPLOYED test Edge '+name);
 }
}
if(isMain(import.meta.url))await runCli(async()=>{if(!process.argv.includes('--deploy'))throw new SafeError('EXPLICIT_TEST_DEPLOY_FLAG_REQUIRED');await deployFunctions();});
