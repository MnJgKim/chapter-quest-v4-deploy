import {test} from 'node:test';import assert from 'node:assert/strict';import '../public/student-session.js';
const project={url:'https://test.supabase.co',anonKey:'public-test'},uid='33333333-3333-4333-8333-333333333333';
const loginData=(token='old',expires=1)=>({access_token:token,refresh_token:token+'-refresh',expires_in:expires,user:{id:uid}});
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
test('student tokens refresh once for concurrent requests and rotate credentials in memory',async()=>{
 let refreshes=0;const seen=[];const session=CQStudentSession.createSession({fetchImpl:async(url,options)=>{if(url.includes('grant_type=password'))return Response.json(loginData());if(url.includes('refresh_token')){refreshes++;await Promise.resolve();return Response.json(loginData('new',3600));}seen.push(new Headers(options.headers).get('Authorization'));return Response.json([]);}});
 await session.login(project,'student@example.test','test');const epoch=session.epoch();await Promise.all([session.request(project.url+'/rpc',{},epoch),session.request(project.url+'/rpc',{},epoch)]);assert.equal(refreshes,1);assert.deepEqual(seen,['Bearer new','Bearer new']);
});
test('logout during refresh discards late tokens; stale request never borrows a new account token',async()=>{
 const waiting=deferred();let reset=0;const updates=[];const session=CQStudentSession.createSession({onReset:()=>reset++,onUpdate:s=>updates.push(s.token),fetchImpl:async url=>url.includes('grant_type=password')?Response.json(loginData()):waiting.promise});
 await session.login(project,'student@example.test','test');const epoch=session.epoch();const pending=session.token(epoch);session.reset();waiting.resolve(Response.json(loginData('late',3600)));await assert.rejects(pending,/STUDENT_SESSION_CHANGED/);assert.deepEqual(updates,['old']);assert.equal(reset,2);await assert.rejects(session.token(epoch),/STUDENT_SESSION_CHANGED/);
});
test('expired refresh or wrong user clears session and does not send data requests',async()=>{
 for(const result of [new Response('',{status:401}),Response.json({...loginData('new',3600),user:{id:'another-user'}})]){
  let calls=0;const session=CQStudentSession.createSession({fetchImpl:async url=>{calls++;return url.includes('grant_type=password')?Response.json(loginData()):result;}});await session.login(project,'student@example.test','test');const epoch=session.epoch();await assert.rejects(session.request(project.url+'/data',{},epoch));assert.equal(calls,2);await assert.rejects(session.token(epoch),/STUDENT_SESSION_CHANGED/);
 }
});
test('late login and late data responses are discarded after reset',async()=>{
 const pending=deferred();let updates=0;const session=CQStudentSession.createSession({onUpdate:()=>updates++,fetchImpl:()=>pending.promise});const login=session.login(project,'student@example.test','test');session.reset();pending.resolve(Response.json(loginData('late',3600)));await assert.rejects(login,/STUDENT_SESSION_CHANGED/);assert.equal(updates,0);
 const body=deferred();const second=CQStudentSession.createSession({fetchImpl:async url=>url.includes('password')?Response.json(loginData('valid',3600)):body.promise});await second.login(project,'student@example.test','test');const request=second.request(project.url+'/data');await new Promise(r=>setImmediate(r));second.reset();body.resolve(Response.json({private:'old account'}));await assert.rejects(request,/STUDENT_SESSION_CHANGED/);
});
