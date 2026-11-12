// Local-only source review. Never import this module into app/public or a Worker.
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {PDFDocument} from 'pdf-lib';
export const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');
const kinds=new Set(['body','handwriting','caption','illustration-text','heading','page-number','no-text']);
export function auditTranscript(manifest,{pdfHash,pageCount,imageHashes}){
 const issues=[],text=[];const issue=(page,code)=>issues.push({page,code});
 if(manifest?.version!==1||manifest.sourceSHA256!==pdfHash||manifest.pageCount!==pageCount)issue(null,'SOURCE_MISMATCH');
 const scope=manifest?.aiPageRange??{start:1,end:pageCount};
 if(!Number.isInteger(scope.start)||!Number.isInteger(scope.end)||scope.start<1||scope.end<scope.start||scope.end>pageCount)issue(null,'INVALID_AI_PAGE_RANGE');
 const pages=Array.isArray(manifest?.pages)?manifest.pages:[];
 if(pages.length!==pageCount)issue(null,'INCOMPLETE_PAGE_SET');
 const seen=new Set();
 for(const p of pages){
  const n=p.filePage;
  if(!Number.isInteger(n)||n<1||n>pageCount||seen.has(n)){issue(n,'INVALID_OR_DUPLICATE_PAGE');continue;}seen.add(n);
  const excluded=n<scope.start||n>scope.end;
  if(excluded){if(p.excludeFromAI!==true||typeof p.exclusionReason!=='string'||!p.exclusionReason.trim())issue(n,'EXCLUSION_REASON_REQUIRED');continue;}
  if(p.excludeFromAI===true)issue(n,'IN_SCOPE_EXCLUSION_FORBIDDEN');
  const hash=imageHashes[n];
  if(!hash||p.imageSHA256!==hash)issue(n,'IMAGE_MISMATCH');
  if(!Object.hasOwn(p,'printedPage')||!(p.printedPage===null||typeof p.printedPage==='string'))issue(n,'PRINTED_PAGE_REQUIRED');
  if(p.regionInventoryChecked!==true)issue(n,'REGION_INVENTORY_UNCHECKED');
  if(!Array.isArray(p.blocks)||!p.blocks.length){issue(n,'NO_REGIONS');continue;}
  const ids=new Set();
  for(const b of p.blocks){
   if(typeof b.id!=='string'||!b.id||ids.has(b.id)){issue(n,'INVALID_REGION_ID');continue;}ids.add(b.id);
   if(!kinds.has(b.kind))issue(n,'INVALID_REGION_KIND');
   if(!Array.isArray(b.box)||b.box.length!==4||b.box.some(v=>!Number.isFinite(v)||v<0||v>1)||b.box[0]>=b.box[2]||b.box[1]>=b.box[3])issue(n,'INVALID_REGION_BOX');
   const a=b.firstPass,c=b.secondPass;
   for(const pass of [a,c])if(!pass||pass.imageChecked!==true||pass.imageSHA256!==hash||typeof pass.text!=='string'||!pass.reviewedAt||!Number.isFinite(Date.parse(pass.reviewedAt)))issue(n,'REVIEW_PASS_REQUIRED');
   if(a?.reviewedAt&&c?.reviewedAt&&Date.parse(c.reviewedAt)<=Date.parse(a.reviewedAt))issue(n,'SECOND_PASS_NOT_LATER');
   if(b.uncertain!==false)issue(n,'UNCERTAINTY_UNRESOLVED');
   if(a?.text!==c?.text)issue(n,'TEXT_DISAGREEMENT'); // No grammar, article or punctuation normalization.
   if(b.kind==='no-text'&&(a?.text!==''||c?.text!==''||!b.reason))issue(n,'NO_TEXT_REASON_REQUIRED');
   if(b.kind!=='no-text'&&!a?.text?.trim())issue(n,'MISSING_TEXT');
   if(a&& !['page-number','no-text'].includes(b.kind))text.push({page:n,id:b.id,text:a.text});
  }
 }
 for(let n=1;n<=pageCount;n++)if(!seen.has(n))issue(n,'MISSING_PAGE');
 // This checks evidence consistency, not whether a human actually found every visible word.
 return {ok:issues.length===0,issues,verifiedText:issues.length?null:text.sort((a,b)=>a.page-b.page).map(x=>`[PDF file page ${x.page}]\n${x.text}`).join('\n\n')};
}
export async function reviewLocal(manifestPath,pdfPath,imageRoot){
 const manifest=JSON.parse(await fs.readFile(manifestPath,'utf8')),bytes=new Uint8Array(await fs.readFile(pdfPath));
 const doc=await PDFDocument.load(bytes,{updateMetadata:false}),pageCount=doc.getPageCount(),imageHashes={};
 for(let n=1;n<=pageCount;n++){
  try{imageHashes[n]=sha256(await fs.readFile(path.join(imageRoot,`page-${String(n).padStart(2,'0')}.png`)));}catch{}
 }
 return auditTranscript(manifest,{pdfHash:sha256(bytes),pageCount,imageHashes});
}
export function assertPrivateOutput(destination,repositoryRoot){
 const file=path.resolve(destination),repo=path.resolve(repositoryRoot);
 if(file===repo||file.startsWith(repo+path.sep))throw Error('PRIVATE_OUTPUT_MUST_BE_OUTSIDE_REPOSITORY');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 const [manifest,pdf,images,output]=process.argv.slice(2);
 if(!output)throw Error('Four local paths required; do not use secrets or public output locations');
 // Reject paths through symlinked directories before any output is written.
 const dir=await fs.realpath(path.dirname(path.resolve(output)));
 const target=path.join(dir,path.basename(output)),repo=await fs.realpath(new URL('../..',import.meta.url));
 assertPrivateOutput(target,repo);
 try{if((await fs.lstat(target)).isSymbolicLink())throw Error('SYMLINK_OUTPUT_FORBIDDEN');}catch(e){if(e.code!=='ENOENT')throw e;}
 const result=await reviewLocal(manifest,pdf,images);
 console.log(JSON.stringify({ok:result.ok,issues:result.issues})); // Never log source text.
 if(!result.ok)process.exitCode=2;
 else await fs.writeFile(target,result.verifiedText,{flag:'wx',mode:0o600});
}
