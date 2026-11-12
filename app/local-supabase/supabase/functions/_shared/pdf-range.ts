import { PDFDocument } from 'npm:pdf-lib@1.17.1';
export async function pdfSha256(bytes:Uint8Array){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(n=>n.toString(16).padStart(2,'0')).join('');}
export async function derivePdfRange(bytes:Uint8Array,start:number,end:number,title:string){
 if(bytes.length<5||bytes.length>50*1024*1024||String.fromCharCode(...bytes.slice(0,5))!=='%PDF-')throw Error('INVALID_SOURCE_PDF');
 const source=await PDFDocument.load(bytes,{updateMetadata:false}),total=source.getPageCount();
 if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<1||end<start||end>total)throw Error('INVALID_PAGE_RANGE');
 if(start===1&&end===total){const sha=await pdfSha256(bytes);return {bytes,source_page_count:total,page_count:total,source_sha256:sha,derived_sha256:sha};}
 const result=await PDFDocument.create(),pages=await result.copyPages(source,Array.from({length:end-start+1},(_,i)=>start+i-1));
 for(const page of pages)result.addPage(page);result.setTitle(title);result.setProducer('Chapter Quest V4 verified range');
 const derived=await result.save();if(derived.length>50*1024*1024)throw Error('DERIVED_PDF_TOO_LARGE');
 return {bytes:derived,source_page_count:total,page_count:end-start+1,source_sha256:await pdfSha256(bytes),derived_sha256:await pdfSha256(derived)};
}
