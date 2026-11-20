// Isolated API transport contract: no production network or student credentials.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app/public/js/student-api.js','utf8');
const uuid='12345678-1234-4234-8234-123456789abc';
function setup(reply, status=200){
 const calls=[];
 const context={module:{exports:{}},globalThis:{},fetch:()=>{throw Error('Unexpected network access')},console};
 vm.runInNewContext(source,context,{filename:'student-api.js'});
 const api=context.module.exports.createStudentAPI({
  url:'https://example-project.supabase.co',anonKey:'test-public-anon-key',
  getAccessToken:async()=> 'isolated-student-token',
  fetchImpl:async(url,options)=>{calls.push({url,options});return {ok:status>=200&&status<300,status,json:async()=>reply};}
 });
 return {api,calls};
}
test('reread completion invokes authenticated RPC and confirms true',async()=>{
 const {api,calls}=setup(true);
 assert.equal(await api.completeReread(uuid),true);
 assert.equal(calls.length,1);
 assert.match(calls[0].url,/\/rest\/v1\/rpc\/cq_v4_complete_reread$/);
 assert.equal(calls[0].options.method,'POST');
 assert.equal(calls[0].options.headers.Authorization,'Bearer isolated-student-token');
 assert.equal(JSON.parse(calls[0].options.body).p_chapter_uuid,uuid);
});
test('reread completion rejects false confirmation',async()=>{
 const {api}=setup(false);
 await assert.rejects(api.completeReread(uuid),/재독서 완료 저장을 확인할 수 없습니다/);
});
test('invalid chapter identifier cannot reach RPC',async()=>{
 const {api,calls}=setup(true);
 await assert.rejects(api.completeReread('bad-id'),/유효하지 않은 챕터 ID/);
 assert.equal(calls.length,0);
});
test('server denial never counts as reread completion',async()=>{
 const {api}=setup({message:'Reread authorization denied'},403);
 await assert.rejects(api.completeReread(uuid),/403/);
});
test('reread status requires server Boolean fields',async()=>{
 const {api}=setup([{required:true,completed:false}]);
 assert.deepEqual(JSON.parse(JSON.stringify(await api.rereadStatus(uuid))),{required:true,completed:false});
});
test('malformed reread status is rejected',async()=>{
 const {api}=setup([{required:'true',completed:false}]);
 await assert.rejects(api.rereadStatus(uuid),/재독서 상태가 올바르지 않습니다/);
});
