import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const parent='11111111-1111-4111-8111-111111111111',student='22222222-2222-4222-8222-222222222222',chapter='44444444-4444-4444-8444-444444444444',origin='https://test.supabase.co';
const source=(await fs.readFile(new URL('./local-supabase/supabase/functions/cq-v4-pdf-parent/index.ts',import.meta.url),'utf8')).replace(/^import .*?;\s*$/m,'');
function app(settings={}){
 let handler,clients=0;const calls=[];
 const createClient=()=>++clients===1?{auth:{getUser:async()=>({data:{user:{id:parent}}})},rpc(name){calls.push(['rpc',name]);if(name==='cq_is_admin')return Promise.resolve({data:settings.student?false:true});const filters=[];return {eq(k,v){filters.push([k,v]);return this},async maybeSingle(){calls.push(['filters',filters]);return {data:settings.denied?null:{submitted_at:settings.pending?null:'2026-11-11',answers:{hasAudio:!settings.noAudio}},error:settings.rpcError?Error('rpc'):null}}}}}:{storage:{from(bucket){return {async createSignedUrl(path,seconds){calls.push(['sign',bucket,path,seconds]);if(settings.missing||settings.mp4&&path.endsWith('.webm'))return {error:Error('missing')};return {data:{signedUrl:(settings.foreign?'https://evil.test':origin)+'/storage/v1/object/sign/'+bucket+'/'+(settings.wrongPath?'other/file.webm':path)+'?token=synthetic'}}}}}}};
 vm.runInNewContext(stripTypeScriptTypes(source),{Request,Response,URL,TextEncoder,crypto,console,createClient,Deno:{env:{get:k=>({SUPABASE_URL:origin,SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'synthetic'}[k])},serve:fn=>handler=fn}});
 return {calls,call:(id=student)=>handler(new Request(origin,{method:'POST',headers:{Authorization:'Bearer synthetic','Content-Type':'application/json'},body:JSON.stringify({action:'audio_download_url',chapter_uuid:chapter,student_user_id:id})}))};
}
test('parent signs only an existing authorized final submission using the caller JWT RPC',async()=>{const a=app();const r=await a.call();assert.equal(r.status,200);assert.match((await r.json()).signed_url,/^\/storage\/v1\/object\/sign\/cq-v4-speaking\//);assert.equal(JSON.stringify(a.calls),JSON.stringify([['rpc','cq_is_admin'],['rpc','cq_v4_parent_submissions'],['filters',[['chapter_uuid',chapter],['child_user_id',student]]],['sign','cq-v4-speaking',student+'/'+chapter+'.webm',120]]));});
for(const [name,settings,status] of [['student',{student:true},403],['other owner or revoked assignment',{denied:true},403],['no final submission',{pending:true},403],['no submitted audio',{noAudio:true},403],['authorization RPC failure',{rpcError:true},503]])test('recording access denies '+name+' before Storage signing',async()=>{const a=app(settings);assert.equal((await a.call()).status,status);assert.ok(!a.calls.some(x=>x[0]==='sign'));});
test('invalid student UUID cannot reach the submission RPC',async()=>{const a=app();assert.equal((await a.call('invalid')).status,400);assert.equal(a.calls.length,1);});
test('recording signing falls back to the actual MP4 file',async()=>{const a=app({mp4:true});const r=await a.call();assert.equal(r.status,200);assert.match((await r.json()).signed_url,/\.mp4\?token=/);});
test('missing recordings do not mint a usable link',async()=>{const a=app({missing:true});assert.equal((await a.call()).status,404);});
for(const [name,settings] of [['foreign origin',{foreign:true}],['different object',{wrongPath:true}]])test('signed audio rejects '+name,async()=>{const a=app(settings);assert.equal((await a.call()).status,500);});
