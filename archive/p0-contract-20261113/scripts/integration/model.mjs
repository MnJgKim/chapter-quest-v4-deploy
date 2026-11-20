import {validateDraft} from '../../worker/index.js';import {loadTarget,needed,isMain,runCli,SafeError,api} from './common.mjs';
export async function modelProbe(target,env,parentToken){
 const source='This is synthetic test content, not a real child record. A child named Alex finds a lost book and asks a librarian to help return it. Alex decides to wait for the owner instead of keeping the book. The librarian thanks Alex for being honest. '.repeat(2);
 const response=await fetch(target.workerOrigin+'/api/generate',{method:'POST',headers:{Origin:target.workerOrigin,Authorization:'Bearer '+parentToken,'Content-Type':'application/json'},body:JSON.stringify({title:'Integration fixture',chapter:'A lost book',source}),redirect:'error',signal:AbortSignal.timeout(60000)});
 if(!response.ok)throw new SafeError('MODEL_WORKER_HTTP_'+response.status);const result=validateDraft(await response.json());
 // Schema acceptance does not establish educational correctness or parent approval.
 if(!result.questions.some(q=>q.kind==='inference')||!result.questions.some(q=>q.kind==='mc'||q.kind==='comprehension'))throw new SafeError('MODEL_PEDAGOGICAL_MIX_MISSING');
 console.log('PASS actual-model-schema-and-question-mix');console.log('MANUAL_REQUIRED factual-correctness-age-level-answer-quality');
}
if(isMain(import.meta.url))await runCli(async()=>{
 if(!process.argv.includes('--run')||!process.argv.includes('--allow-model-cost'))throw new SafeError('EXPLICIT_MODEL_COST_OPT_IN_REQUIRED');
 const target=await loadTarget();const token=needed(process.env,'CQ_TEST_PARENT_ACCESS_TOKEN');
 const identity=await api(target,process.env,'/auth/v1/user',{method:'GET',token});if(!identity.ok)throw new SafeError('TEST_PARENT_TOKEN_INVALID');
 const role=await api(target,process.env,'/rest/v1/rpc/cq_v4_my_role',{token,body:{}});if(!role.ok||await role.json()!=='parent')throw new SafeError('TEST_PARENT_ROLE_REQUIRED');
 await modelProbe(target,process.env,token);
});
