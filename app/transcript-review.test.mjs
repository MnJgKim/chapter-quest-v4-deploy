import test from 'node:test';import assert from 'node:assert/strict';
import {auditTranscript,assertPrivateOutput} from './tools/transcript-review.mjs';
const evidence={pdfHash:'pdf',pageCount:1,imageHashes:{1:'image'}};
function fixture(){return {version:1,sourceSHA256:'pdf',pageCount:1,pages:[{filePage:1,printedPage:'iv',imageSHA256:'image',regionInventoryChecked:true,blocks:[{id:'h',kind:'handwriting',box:[0,0,1,1],uncertain:false,firstPass:{text:'A small boat.',imageChecked:true,imageSHA256:'image',reviewedAt:'2026-11-12T01:00:00Z'},secondPass:{text:'A small boat.',imageChecked:true,imageSHA256:'image',reviewedAt:'2026-11-12T02:00:00Z'}}]}]};}
test('two image-bound passes export exact text without printed-page conflation',()=>{const r=auditTranscript(fixture(),evidence);assert.equal(r.ok,true);assert.match(r.verifiedText,/PDF file page 1/);assert.match(r.verifiedText,/A small boat\./);});
for(const [name,change,code] of [
 ['added word',m=>m.pages[0].blocks[0].secondPass.text='A very small boat.','TEXT_DISAGREEMENT'],
 ['omitted word',m=>m.pages[0].blocks[0].secondPass.text='Small boat.','TEXT_DISAGREEMENT'],
 ['uncertain handwriting',m=>m.pages[0].blocks[0].uncertain=true,'UNCERTAINTY_UNRESOLVED'],
 ['unchecked image',m=>m.pages[0].blocks[0].secondPass.imageChecked=false,'REVIEW_PASS_REQUIRED'],
 ['changed image',m=>m.pages[0].imageSHA256='different','IMAGE_MISMATCH'],
 ['changed PDF',m=>m.sourceSHA256='different','SOURCE_MISMATCH'],
 ['missing page',m=>m.pages=[],'MISSING_PAGE'],
 ['missing printed label',m=>delete m.pages[0].printedPage,'PRINTED_PAGE_REQUIRED'],
 ['no second pass',m=>delete m.pages[0].blocks[0].secondPass,'REVIEW_PASS_REQUIRED'],
 ['unchecked inventory',m=>m.pages[0].regionInventoryChecked=false,'REGION_INVENTORY_UNCHECKED']
])test('export blocked: '+name,()=>{const m=fixture();change(m);const r=auditTranscript(m,evidence);assert.equal(r.ok,false);assert.equal(r.verifiedText,null);assert.ok(r.issues.some(x=>x.code===code));});
test('refuses any export inside repository, including public assets',()=>{assert.throws(()=>assertPrivateOutput('/repo/app/public/text.txt','/repo'),/PRIVATE_OUTPUT/);assert.throws(()=>assertPrivateOutput('/repo/private.txt','/repo'),/PRIVATE_OUTPUT/);assert.doesNotThrow(()=>assertPrivateOutput('/private/lesson.txt','/repo'));});
test('no-text region requires an explicit image-reviewed reason',()=>{const m=fixture(),b=m.pages[0].blocks[0];b.kind='no-text';b.firstPass.text='';b.secondPass.text='';assert.equal(auditTranscript(m,evidence).ok,false);b.reason='Illustration contains no visible lettering';assert.equal(auditTranscript(m,evidence).ok,true);});
test('a description is not accepted as a source-text region type',()=>{const m=fixture();m.pages[0].blocks[0].kind='editorial-description';assert.equal(auditTranscript(m,evidence).ok,false);});
test('line breaks are retained, not silently normalized',()=>{const m=fixture();m.pages[0].blocks[0].firstPass.text='Small\nboat';m.pages[0].blocks[0].secondPass.text='Small\nboat';assert.ok(auditTranscript(m,evidence).verifiedText.endsWith('Small\nboat'));});
test('second image review must be later than first',()=>{const m=fixture();m.pages[0].blocks[0].secondPass.reviewedAt=m.pages[0].blocks[0].firstPass.reviewedAt;assert.ok(auditTranscript(m,evidence).issues.some(i=>i.code==='SECOND_PASS_NOT_LATER'));});
