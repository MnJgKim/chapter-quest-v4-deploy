import {test} from 'node:test';import assert from 'node:assert/strict';
import {createWorker,validateDraft,AIQuota} from '../worker/index.js';
const uid='11111111-1111-4111-8111-111111111111';
const draft={questions:[{kind:'mc',text:'What happened?',options:['A','B'],correct:0},{kind:'inference',text:'Why?',sample:'Because of the event.'}],vocabulary:[{word:'event',meaning:'사건',example:'An event occurred.'}],writingPrompt:'Describe the story.',speakingPrompt:'Summarize the chapter.'};
const source={title:'Book',chapter:'Chapter 1',source:'A chapter source. '.repeat(20)};
function fixture({role='parent',provider,quota=204}={}){
 const calls=[];const env={SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'public-test',OPENAI_API_KEY:'model-test',AI_QUOTA:{idFromName:s=>s,get:()=>({fetch:async()=>new Response(null,{status:quota})})},ASSETS:{fetch:()=>new Response('static assets')}};
 const worker=createWorker(async(url,options)=>{calls.push({url,options});if(url.endsWith('/auth/v1/user'))return Response.json({id:uid});if(url.endsWith('/rpc/cq_v4_my_role'))return Response.json(role);return provider||Response.json({choices:[{finish_reason:'stop',message:{content:JSON.stringify(draft)}}]});});
 return {worker,env,calls};
}
const req=(body=source,headers={})=>new Request('https://app.example.test/api/generate',{method:'POST',headers:{Origin:'https://app.example.test',Authorization:'Bearer parent-test','Content-Type':'application/json',...headers},body:JSON.stringify(body)});
test('AI worker serves assets and rejects unknown APIs, methods, missing auth and cross-origin',async()=>{
 const {worker,env,calls}=fixture();assert.equal(await (await worker.fetch(new Request('https://app.example.test/'),env)).text(),'static assets');
 assert.equal((await worker.fetch(new Request('https://app.example.test/api/missing'),env)).status,404);
 assert.equal((await worker.fetch(new Request('https://app.example.test/api/generate'),env)).status,405);
 assert.equal((await worker.fetch(req(source,{Authorization:''}),env)).status,401);assert.equal((await worker.fetch(req(source,{Origin:'https://evil.example.test'}),env)).status,403);assert.equal(calls.length,0);
});
test('AI worker requires parent database role; code header alone never authorizes',async()=>{
 const {worker,env,calls}=fixture({role:'student'});assert.equal((await worker.fetch(req(),env)).status,403);assert.equal(calls.length,2);
 assert.equal((await worker.fetch(req(source,{Authorization:'','X-CQ-Access':'legacy-code'}),env)).status,401);
});
test('AI worker validates source limits and quota before calling the provider',async()=>{
 const {worker,env,calls}=fixture();assert.equal((await worker.fetch(req({...source,source:'short'}),env)).status,400);assert.equal((await worker.fetch(req({...source,source:'x'.repeat(45001)}),env)).status,400);assert.equal((await worker.fetch(req({...source,pad:'x'.repeat(200001)}),env)).status,413);assert.equal(calls.some(c=>c.url.includes('openai.com')),false);
 const limited=fixture({quota:429});assert.equal((await limited.worker.fetch(req(),limited.env)).status,429);assert.equal(limited.calls.some(c=>c.url.includes('openai.com')),false);
 const missing=fixture();delete missing.env.AI_QUOTA;assert.equal((await missing.worker.fetch(req(),missing.env)).status,503);
});
test('AI worker returns validated compatible draft, isolates model key and marks source untrusted',async()=>{
 const {worker,env,calls}=fixture();const response=await worker.fetch(req(),env);assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');const body=await response.json();assert.equal(body.questions[1].sample,draft.questions[1].sample);
 const model=calls.at(-1);assert.equal(model.options.headers.Authorization,'Bearer model-test');assert.equal(calls[0].options.headers.Authorization,'Bearer parent-test');assert.equal(calls[0].options.headers.apikey,'public-test');const sent=JSON.parse(model.options.body);assert.match(sent.messages[0].content,/untrusted/);assert.deepEqual(JSON.parse(sent.messages[1].content),source);assert.equal(JSON.stringify(body).includes('model-test'),false);
});
test('AI worker rejects malformed, truncated and invalid model results without leaking upstream errors',async()=>{
 for(const provider of [Response.json({choices:[{finish_reason:'length',message:{content:'{}'}}]}),Response.json({choices:[{finish_reason:'stop',message:{content:'not-json'}}]}),Response.json({choices:[{finish_reason:'stop',message:{content:'{}'}}]}),new Response('private provider details',{status:500})]){
  const {worker,env}=fixture({provider});const response=await worker.fetch(req(),env);assert.equal(response.status,502);assert.equal((await response.text()).includes('private provider details'),false);
 }
 for(const patch of [{questions:[{kind:'mc',text:'Q',options:['A','B'],correct:9}]},{questions:[{kind:'inference',text:'Q',sample:''}]},{vocabulary:[{word:'',meaning:'x',example:''}]},{writingPrompt:''}])assert.throws(()=>validateDraft({...draft,...patch}),/INVALID_AI_OUTPUT/);
});
test('Durable quota persists across instances and expires after an hour',async()=>{
 let saved;const storage={transaction:async callback=>callback({get:async()=>saved,put:async(_key,value)=>{saved=structuredClone(value)}})};
 const first=new AIQuota({storage});for(let i=0;i<10;i++)assert.equal((await first.fetch(new Request('https://quota',{method:'POST'}))).status,204);
 const restored=new AIQuota({storage});assert.equal((await restored.fetch(new Request('https://quota',{method:'POST'}))).status,429);saved=saved.map(()=>Date.now()-3600001);assert.equal((await restored.fetch(new Request('https://quota',{method:'POST'}))).status,204);
});
