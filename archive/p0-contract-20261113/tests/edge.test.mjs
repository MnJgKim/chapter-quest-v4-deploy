import {test} from 'node:test';import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/_shared/handlers.ts';
import {createGateway,HttpError} from '../supabase/functions/_shared/gateway.ts';
const parent='11111111-1111-4111-8111-111111111111',chapter='33333333-3333-4333-8333-333333333333',origin='https://app.example.test';
function stub(role='parent'){
 const calls=[];const gateway={user:async token=>{calls.push(['user',token]);return {id:parent}},rpc:async(token,name,args)=>{calls.push([name,args]);if(name==='cq_v4_my_role')return role;if(name==='cq_v4_parent_pdf')return {path:`${parent}/${chapter}/original.pdf`,bucket:'cq-v4-originals'};if(name==='cq_v4_pdf_access')return `${parent}/${chapter}/original.pdf`;return true},uploadUrl:async path=>{calls.push(['upload',path]);return {token:'test-upload-token'}},pdfHeader:async()=>new TextEncoder().encode('%PDF-'),finalize:async(...args)=>{calls.push(['finalize',...args]);return true},signPdf:async path=>{calls.push(['sign',path]);return 'https://test.supabase.co/storage/v1/object/sign/cq-v4-originals/'+path+'?token=test'},invite:async email=>{calls.push(['invite',email])}};return {calls,gateway};
}
function request(body,extra={}){return new Request(origin,{method:'POST',headers:{Origin:origin,Authorization:'Bearer test-user-token','Content-Type':'application/json',...extra},body:JSON.stringify(body)});}
test('Edge rejects missing auth, wrong origins, methods, malformed/oversized JSON',async()=>{
 const {gateway,calls}=stub();const handler=createHandler('pdf-parent',gateway,origin);
 assert.equal((await handler(new Request(origin,{method:'POST',body:'{}'}))).status,401);
 assert.equal((await handler(request({}, {Origin:'https://evil.example.test'}))).status,403);
 assert.equal((await handler(new Request(origin))).status,405);
 assert.equal((await handler(new Request(origin,{method:'OPTIONS',headers:{Origin:origin}}))).status,204);
 assert.equal((await handler(request({padding:'x'.repeat(8193)}))).status,413);
 const malformed=new Request(origin,{method:'POST',headers:{Authorization:'Bearer test'},body:'{'});assert.equal((await handler(malformed)).status,400);
 assert.equal(calls.filter(c=>c[0]==='upload').length,0);
});
test('student cannot issue accounts or sign parent PDF uploads',async()=>{
 const {gateway,calls}=stub('student');assert.equal((await createHandler('student-account',gateway,origin)(request({email:'child@example.test'}))).status,403);
 assert.equal((await createHandler('pdf-parent',gateway,origin)(request({action:'upload_url',chapter_uuid:chapter}))).status,403);assert.equal(calls.some(c=>c[0]==='upload'||c[0]==='invite'),false);
});
test('account issuance checks role and reserves quota before Auth email invitation',async()=>{
 const {gateway,calls}=stub();const handler=createHandler('student-account',gateway,origin);
 assert.equal((await handler(request({email:'bad'}))).status,400);
 const response=await handler(request({email:'child@example.test'}));assert.equal(response.status,200);assert.deepEqual(await response.json(),{invited:true});
 assert.ok(calls.findIndex(c=>c[0]==='cq_v4_reserve_account_invite')<calls.findIndex(c=>c[0]==='invite'));
 gateway.rpc=async()=>{throw new HttpError(403,'FORBIDDEN')};assert.equal((await handler(request({email:'child@example.test'}))).status,403);assert.equal(calls.filter(c=>c[0]==='invite').length,1);
});
test('PDF upload URL uses authorized owner/chapter path; mismatched path is rejected',async()=>{
 const {gateway,calls}=stub();const handler=createHandler('pdf-parent',gateway,origin);const res=await handler(request({action:'upload_url',chapter_uuid:chapter}));assert.equal(res.status,200);assert.equal((await res.json()).token,'test-upload-token');
 gateway.rpc=async(_token,name)=>name==='cq_v4_my_role'?'parent':{path:`other/${chapter}/original.pdf`};assert.equal((await handler(request({action:'upload_url',chapter_uuid:chapter}))).status,403);assert.equal(calls.filter(c=>c[0]==='upload').length,1);
});
test('PDF finalization requires owned path and real PDF signature before privileged DB call',async()=>{
 const {gateway,calls}=stub();const handler=createHandler('pdf-parent',gateway,origin);
 gateway.pdfHeader=async()=>new TextEncoder().encode('HTML!');assert.equal((await handler(request({action:'finalize_upload',chapter_uuid:chapter}))).status,400);assert.equal(calls.some(c=>c[0]==='finalize'),false);
 gateway.pdfHeader=async()=>new TextEncoder().encode('%PDF-');assert.equal((await handler(request({action:'finalize_upload',chapter_uuid:chapter}))).status,200);assert.deepEqual(calls.find(c=>c[0]==='finalize'),['finalize',chapter,parent]);
});
test('student PDF URL is minted only after assignment RPC; revoked/foreign chapter is denied',async()=>{
 const {gateway,calls}=stub('student');const handler=createHandler('pdf-link',gateway,origin,()=>1000000);
 const res=await handler(request({chapter_uuid:chapter}));assert.equal(res.status,200);assert.equal((await res.json()).expires_at,new Date(1120000).toISOString());
 gateway.rpc=async(_token,name)=>{if(name==='cq_v4_my_role')return 'student';throw new HttpError(403,'FORBIDDEN')};assert.equal((await handler(request({chapter_uuid:chapter}))).status,403);assert.equal(calls.filter(c=>c[0]==='sign').length,1);
});
test('HTTP gateway separates user and service credentials and never puts them in URLs',async()=>{
 const seen=[];const fake=async(url,options)=>{seen.push({url,options});return Response.json(url.endsWith('/user')?{id:parent}:url.includes('/sign/')?{signedURL:'/object/sign/cq-v4-originals/file?token=signed'}:true)};
 const gateway=createGateway({url:'https://test.supabase.co',anonKey:'public-test',serviceKey:'service-test',origin},fake);
 await gateway.user('user-test');await gateway.rpc('user-test','cq_v4_my_role');await gateway.finalize(chapter,parent);await gateway.invite('child@example.test');
 assert.equal(seen[0].options.headers.Authorization,'Bearer user-test');assert.equal(seen[2].options.headers.Authorization,'Bearer service-test');assert.equal(seen[2].options.headers.apikey,'service-test');assert.equal(seen.some(x=>x.url.includes('service-test')||x.url.includes('user-test')),false);
 assert.equal(new URL(seen[3].url).searchParams.get('redirect_to'),origin+'/');
 assert.deepEqual(JSON.parse(seen[3].options.body),{email:'child@example.test'});
 const signed=await gateway.signPdf('file');assert.equal(new URL(signed).pathname,'/storage/v1/object/sign/cq-v4-originals/file');
});
test('HTTP PDF header reader handles split chunks and cancels after five bytes',async()=>{
 let cancelled=false;const stream=new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('%P'));c.enqueue(new TextEncoder().encode('DF-more data'));},cancel(){cancelled=true}});
 const gateway=createGateway({url:'https://test.supabase.co',anonKey:'test',serviceKey:'test',origin},async()=>new Response(stream));
 assert.equal(new TextDecoder().decode(await gateway.pdfHeader('file')),'%PDF-');assert.equal(cancelled,true);
});
