import {writeFile,chmod} from 'node:fs/promises';import {loadTarget,needed,isMain,runCli,SafeError,root} from './common.mjs';
export async function workerVars(env=process.env){
 const target=await loadTarget(env);const vars={SUPABASE_URL:target.supabaseUrl,SUPABASE_ANON_KEY:needed(env,'CQ_TEST_SUPABASE_ANON_KEY'),OPENAI_API_KEY:needed(env,'CQ_TEST_OPENAI_API_KEY'),AI_MODEL:'gpt-4.1-mini'};
 // JSON string values are valid dotenv quoted values; never print, overwrite or pass keys in command arguments.
 const file=new URL('integration/.dev.vars',root);await writeFile(file,Object.entries(vars).map(([k,v])=>k+'='+JSON.stringify(v)).join('\n')+'\n',{flag:'wx',mode:0o600});await chmod(file,0o600);console.log('WROTE ignored integration/.dev.vars (mode 0600); no deployment');
}
if(isMain(import.meta.url))await runCli(async()=>{if(!process.argv.includes('--write'))throw new SafeError('EXPLICIT_WRITE_FLAG_REQUIRED');await workerVars();});
