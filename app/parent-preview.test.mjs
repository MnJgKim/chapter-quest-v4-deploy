import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('./edge-functions/cq-v4-parent-preview/index.ts',import.meta.url),'utf8')
 .replace(/^import .*;\s*$/m,'')
 .replace('const reply=(body:unknown,status=200)', 'const reply=(body,status=200)')
 .replace('let input:{chapter_uuid?:unknown};','let input;');
const chapter='cda5aa92-39e5-4286-9595-5d80ca779b8f',parent='967982a4-19f9-4a32-a2d5-976f4569091f';
function setup({user=parent,isAdmin=true,owner=parent,published=true,ready=true,sign=true}={}){
 let handler,signs=0,writes=0;
 const mockClient=(_url,key)=>key==='service-secret'?{
  from(table){return {select(){return {eq(field,value){
   if(table==='cq_v4_pdf_chapters')return {eq(_field,uid){return {maybeSingle:async()=>({data:uid===owner?{chapter_id:chapter,title:'The Dark Woods',storage_path:owner+'/'+chapter+'.pdf',pdf_ready:ready}:null,error:null})}};
   return {maybeSingle:async()=>({data:published?{questions:[{question:'Where?'}],vocabulary:[],writing_prompt:'',speaking_prompt:'',published_at:'2026-11-13T00:00:00Z',approval_id:null,approval_hash:null}:null,error:null})};
  }}},insert(){writes++;throw Error('WRITE')},update(){writes++;throw Error('WRITE')},delete(){writes++;throw Error('WRITE')}}},
  storage:{from(){return {createSignedUrl:async()=>{signs++;return {data:sign?{signedUrl:'https://project.supabase.co/storage/v1/object/sign/cq-v4-originals/'+owner+'/'+chapter+'.pdf?token=sample'}:null,error:sign?null:{message:'failed'}}}}}}
 }:{
  auth:{getUser:async()=>({data:{user:user?{id:user}:null},error:null})},
  rpc:async()=>({data:isAdmin,error:null})
 };
 const ctx={Deno:{env:{get:key=>({SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service-secret'})[key]},serve:fn=>{handler=fn}},createClient:mockClient,Response,URL,Date,JSON,Number,String,Error,RegExp};
 vm.runInNewContext(source,ctx);
 return {async request(body={chapter_uuid:chapter},token='Bearer valid',method='POST'){
  const req=new Request('https://project.supabase.co/functions/v1/cq-v4-parent-preview',{method,headers:{authorization:token,'content-type':'application/json'},...(method==='POST'?{body:typeof body==='string'?body:JSON.stringify(body)}:{})});
  const res=await handler(req);return {status:res.status,data:await res.json()};
 },get writes(){return writes},get signs(){return signs}};
}
test('verified parent receives published questions and short-lived PDF URL without writes',async()=>{
 const app=setup();const result=await app.request();assert.equal(result.status,200);assert.equal(result.data.questions.length,1);assert.match(result.data.signed_url,/cq-v4-originals/);assert.equal(app.writes,0);assert.equal(app.signs,1);
});
test('unauthenticated request fails closed',async()=>{const app=setup();assert.equal((await app.request({},'')).status,401);assert.equal(app.signs,0)});
test('student cannot preview',async()=>{const app=setup({isAdmin:false});assert.equal((await app.request()).status,403);assert.equal(app.signs,0)});
test('different parent cannot preview',async()=>{const app=setup({owner:'a1111111-1111-4111-8111-111111111111'});assert.equal((await app.request()).status,403);assert.equal(app.signs,0)});
test('unpublished chapter cannot preview',async()=>{const app=setup({published:false});assert.equal((await app.request()).status,404);assert.equal(app.signs,0)});
test('unverified PDF cannot preview',async()=>{const app=setup({ready:false});assert.equal((await app.request()).status,409);assert.equal(app.signs,0)});
test('invalid chapter and JSON rejected',async()=>{const app=setup();assert.equal((await app.request({chapter_uuid:'bad'})).status,400);assert.equal((await app.request('{broken')).status,400);assert.equal(app.signs,0)});
test('signed URL failure fails closed',async()=>{const app=setup({sign:false});assert.equal((await app.request()).status,503);assert.equal(app.writes,0)});
