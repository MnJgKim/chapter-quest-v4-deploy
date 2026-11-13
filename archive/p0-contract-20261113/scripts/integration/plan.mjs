import {migrations,isMain,runCli} from './common.mjs';
export async function plan(env=process.env){
 const files=await migrations();console.log('OFFLINE PLAN: no network, database changes or deployments');
 for(const {name,sha256} of files)console.log(name+' sha256='+sha256);
 for(const name of ['CQ_TEST_TARGET_FILE','CQ_TEST_CONFIRMED_PROJECT_REF','CQ_TEST_SUPABASE_ANON_KEY','CQ_TEST_SERVICE_ROLE_KEY','CQ_TEST_DATABASE_URL','CQ_TEST_OPENAI_API_KEY','CQ_TEST_INVITE_EMAIL','SUPABASE_ACCESS_TOKEN','CQ_TEST_SUPABASE_CLI','CQ_TEST_PARENT_ACCESS_TOKEN'])console.log(name+': '+(env[name]?'set':'unset'));
 console.log('Edge functions: cq-v4-student-account, cq-v4-pdf-parent, cq-v4-pdf-link');
}
if(isMain(import.meta.url))await runCli(()=>plan());
