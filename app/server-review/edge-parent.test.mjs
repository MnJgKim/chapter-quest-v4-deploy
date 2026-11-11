import fs from 'node:fs/promises';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import test from 'node:test';
import assert from 'node:assert/strict';
async function load(relative,settings={}){
 const source=(await fs.readFile(new URL(relative,import.meta.url),'utf8')).replace(/^import .*?;\s*$/m,'');
 let handler,clients=0;const calls=[];
 const createClient=()=>{
  clients++;
  if(clients===1)return {auth:{getUser:async()=>settings.noUser?{data:{user:null},error:Error('No user')}:{data:{user:{id:'11111111-1111-4111-8111-111111111111'}}}},rpc:async(name)=>{calls.push(['rpc',name]);return {data:settings.isParent??false,error:settings.roleError?Error('role error'):null};}};
  return {from(table){calls.push(['table',table]);const q={select(){return q;},eq(){return q;},order(){return q;},limit(){return q;},insert(){calls.push(['write',table]);return Promise.resolve({error:null});},then(resolve){return Promise.resolve({data:[],error:null}).then(resolve);}};return q;}};
 };
 const context=vm.createContext({Request,Response,URL,TextEncoder,crypto,Set,Number,JSON,console,createClient,Deno:{env:{get:n=>({SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'public-key',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service-key'}[n])},serve:fn=>handler=fn}});
 vm.runInContext(stripTypeScriptTypes(source),context);
 return {call:(action='list_chapters',authorization='Bearer synthetic-token',method='POST')=>handler(new Request('https://test.supabase.co/functions/v1/cq-v4-pdf-parent',{method,headers:{Authorization:authorization,'Content-Type':'application/json'},...(method==='POST'?{body:JSON.stringify({action,title:'Synthetic chapter'})}:{})})),calls,clients:()=>clients};
}
const candidate='./candidate/cq-v4-pdf-parent/index.ts',baseline='./backup/cq-v4-pdf-parent/index.ts';
test('baseline reproduces missing parent role guard with mocked clients',async()=>{const app=await load(baseline,{isParent:false});assert.equal((await app.call('create_chapter')).status,200);assert.ok(app.calls.some(c=>c[0]==='write'));});
test('authenticated student cannot create privileged service client',async()=>{const app=await load(candidate,{isParent:false});assert.equal((await app.call('create_chapter')).status,403);assert.equal(app.clients(),1);assert.ok(!app.calls.some(c=>c[0]==='write'));});
test('unknown user cannot list parent data',async()=>{const app=await load(candidate,{isParent:false});assert.equal((await app.call()).status,403);assert.ok(!app.calls.some(c=>c[0]==='table'));});
test('truthy non-boolean parent result fails closed',async()=>{const app=await load(candidate,{isParent:1});assert.equal((await app.call()).status,403);});
test('role service error fails closed',async()=>{const app=await load(candidate,{isParent:true,roleError:true});assert.equal((await app.call()).status,503);assert.equal(app.clients(),1);});
test('invalid identity rejected before role lookup',async()=>{const app=await load(candidate,{noUser:true});assert.equal((await app.call()).status,401);assert.equal(app.calls.length,0);});
test('missing bearer rejected before creating clients',async()=>{const app=await load(candidate);assert.equal((await app.call('list_chapters','')).status,401);assert.equal(app.clients(),0);});
test('valid parent can use chapter list',async()=>{const app=await load(candidate,{isParent:true});const response=await app.call();assert.equal(response.status,200);assert.deepEqual(await response.json(),{chapters:[]});});
test('valid parent can create own new chapter',async()=>{const app=await load(candidate,{isParent:true});assert.equal((await app.call('create_chapter')).status,200);assert.ok(app.calls.some(c=>c[0]==='write'));});
test('preflight and unsupported methods do not create clients',async()=>{const app=await load(candidate);assert.equal((await app.call('list_chapters','','OPTIONS')).status,204);assert.equal((await app.call('list_chapters','','GET')).status,405);assert.equal(app.clients(),0);});
