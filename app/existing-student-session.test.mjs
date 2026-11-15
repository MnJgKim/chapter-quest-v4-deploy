import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const ctx=vm.createContext({URL,atob});vm.runInContext(readFileSync(new URL('./public/js/existing-student-session.js',import.meta.url),'utf8'),ctx);
const inspect=ctx.CQExistingStudentSession.inspect,uid='11111111-1111-4111-8111-111111111111';
const token=exp=>'header.'+Buffer.from(JSON.stringify({exp})).toString('base64url')+'.signature';
async function run({raw=JSON.stringify({access_token:token(2000),refresh_token:'NEVER_USE'}),user={id:uid,is_anonymous:true},rows=[{student_user_id:uid}],authStatus=200,now=1000000,url='https://synthetic.supabase.co',throws=false}={}){
 const calls=[],keys=[];const result=await inspect({project:{url,anonKey:'synthetic'},now:()=>now,storage:{getItem(k){keys.push(k);return raw},setItem(){throw Error('write forbidden')},removeItem(){throw Error('delete forbidden')}},fetchImpl:async(u,o)=>{calls.push({u,o});if(throws)throw Error('offline');return {status:calls.length===1?authStatus:200,ok:calls.length===1?authStatus===200:true,json:async()=>calls.length===1?user:rows}}});
 assert(calls.every(c=>c.o.method==='GET'&&c.o.redirect==='error'));assert(!calls.some(c=>c.u.includes('token?')||c.u.includes('signup')));return {result,calls,keys};
}
test('verified anonymous identity and exact existing enrollment resume without writes or refresh',async()=>{const {result,calls,keys}=await run();assert.equal(result.status,'ready');assert.equal(result.session.uid,uid);assert.equal(calls.length,2);assert.deepEqual(keys,['sb-synthetic-auth-token']);assert(calls[1].u.endsWith('eq.'+uid));});
for(const [name,options,status] of [
 ['absent',{raw:null},'absent'],['damaged',{raw:'{'},'unreadable'],['invalid token',{raw:'{}'},'invalid'],['rejected token',{authStatus:401},'expired'],['expired',{now:2000000},'expired'],['nonanonymous',{user:{id:uid,is_anonymous:false}},'not-anonymous'],['unlinked',{rows:[]},'unlinked'],['foreign row',{rows:[{student_user_id:'other'}]},'unlinked'],['ambiguous',{rows:[{student_user_id:uid},{student_user_id:uid}]},'unlinked'],['offline',{throws:true},'unavailable'],['foreign origin',{url:'https://example.test'},'configuration']])test(name+' fails closed and preserves stored record',async()=>assert.equal((await run(options)).result.status,status));
test('legacy currentSession wrapper supported without trusting saved user identity',async()=>{const {result}=await run({raw:JSON.stringify({currentSession:{access_token:token(2000),user:{id:'forged'}}})});assert.equal(result.session.uid,uid)});
