// Mocked runtime contract: exercises the actual PDF transport without network, credentials or uploads.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {createPdfTransport}=require('../public/js/pdf-transport.js');
const base='https://example.supabase.co';
const chapter='11111111-1111-4111-8111-111111111111';
const owner='22222222-2222-4222-8222-222222222222';
const now=Date.parse('2026-11-17T12:00:00Z');
const signed=base+'/storage/v1/object/sign/cq-v4-originals/'+owner+'/'+chapter+'.pdf?token=offline';
const pdf=new TextEncoder().encode('%PDF-1.7 mock');
function harness(link={},download={}){
 const calls=[];
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});
  if(calls.length===1)return {ok:true,json:async()=>({signed_url:signed,expires_at:new Date(now+60000).toISOString(),page_count:2,...link})};
  return {ok:true,headers:{get:key=>key==='content-type'?(download.type||'application/pdf'):null},arrayBuffer:async()=>download.bytes||pdf.buffer};
 };
 return {calls,transport:createPdfTransport({url:base,anonKey:'offline',getAccessToken:async()=> 'mock-jwt',fetchImpl,now:()=>now})};
}
test('valid brokered PDF requires authenticated function request and matching signed download',async()=>{
 const {calls,transport}=harness();
 let pages;
 const bytes=await transport.getPdf(chapter,{onMetadata:meta=>pages=meta.page_count});
 assert.equal(new Uint8Array(bytes).byteLength,pdf.byteLength);
 assert.equal(pages,2);
 assert.equal(calls.length,2);
 assert.equal(calls[0].url,base+'/functions/v1/cq-v4-pdf-link');
 assert.equal(calls[0].options.headers.Authorization,'Bearer mock-jwt');
 assert.equal(calls[1].url,signed);
});
for(const [name,link,expected] of [
 ['different origin',{signed_url:'https://evil.example/storage/v1/object/sign/cq-v4-originals/'+owner+'/'+chapter+'.pdf?token=x'},'UNTRUSTED_PDF_URL'],
 ['different chapter',{signed_url:base+'/storage/v1/object/sign/cq-v4-originals/'+owner+'/33333333-3333-4333-8333-333333333333.pdf?token=x'},'PDF_OBJECT_MISMATCH'],
 ['missing signature',{signed_url:signed.split('?')[0]},'UNSIGNED_PDF_URL'],
 ['expired link',{expires_at:new Date(now+1000).toISOString()},'INVALID_PDF_LINK_EXPIRY'],
 ['overlong link',{expires_at:new Date(now+11*60000).toISOString()},'INVALID_PDF_LINK_EXPIRY']
])test('reject '+name+' before downloading',async()=>{
 const {calls,transport}=harness(link);
 await assert.rejects(transport.getPdf(chapter),e=>e.message===expected);
 assert.equal(calls.length,1);
});
test('reject non-PDF response content and forged PDF bytes',async()=>{
 await assert.rejects(harness({}, {type:'text/html'}).transport.getPdf(chapter),e=>e.message==='INVALID_PDF_CONTENT_TYPE');
 await assert.rejects(harness({}, {bytes:new TextEncoder().encode('HELLO!').buffer}).transport.getPdf(chapter),e=>e.message==='INVALID_PDF_SIGNATURE');
});
