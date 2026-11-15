// Private server-side download. Enforce limits while reading, before PDF parsing.
const MAX_PDF_BYTES=50*1024*1024;
export async function downloadPdfBytes(url:string,service:string,path:string,fetchImpl:typeof fetch=fetch,timeoutMs=30000,maxBytes=MAX_PDF_BYTES){
 const base=new URL(url);
 if(!['https:','http:'].includes(base.protocol)||base.username||base.password||base.search||base.hash||base.pathname!=='/'||!service||!Number.isSafeInteger(maxBytes)||maxBytes<5||maxBytes>MAX_PDF_BYTES||!Number.isSafeInteger(timeoutMs)||timeoutMs<1)throw Error('PDF_DOWNLOAD_CONFIGURATION');
 if(!/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.pdf$/i.test(path))throw Error('PDF_DOWNLOAD_PATH');
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),timeoutMs);
 let reader:ReadableStreamDefaultReader<Uint8Array>|undefined;
 try{
  const response=await fetchImpl(base.origin+'/storage/v1/object/authenticated/cq-v4-originals/'+path,{method:'GET',headers:{apikey:service,Authorization:'Bearer '+service},redirect:'error',cache:'no-store',signal:controller.signal});
  if(!response.ok||!response.body)throw Error('PDF_DOWNLOAD_FAILED');
  reader=response.body.getReader();
  const rawLength=response.headers.get('content-length'),encoding=response.headers.get('content-encoding');
  const length=rawLength!==null&&/^[0-9]+$/.test(rawLength)?Number(rawLength):null;
  if(length!==null&&(!Number.isSafeInteger(length)||length>maxBytes))throw Error('PDF_DOWNLOAD_TOO_LARGE');
  // Encoded response lengths describe transport bytes, not decoded stream size.
  const expected=!encoding||encoding==='identity'?length:null;
  const buffer=expected!==null?new Uint8Array(expected):null,chunks:Uint8Array[]=[];let size=0;
  while(true){
   if(controller.signal.aborted)throw Error('PDF_DOWNLOAD_TIMEOUT');
   const {done,value}=await reader.read();if(done)break;
   size+=value.byteLength;if(size>maxBytes||(expected!==null&&size>expected))throw Error('PDF_DOWNLOAD_TOO_LARGE');
   if(buffer)buffer.set(value,size-value.byteLength);else chunks.push(value);
  }
  if(controller.signal.aborted)throw Error('PDF_DOWNLOAD_TIMEOUT');
  if(expected!==null&&size!==expected)throw Error('PDF_DOWNLOAD_TRUNCATED');
  const bytes=buffer||new Uint8Array(size);if(!buffer){let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}}
  if(size<5||String.fromCharCode(...bytes.subarray(0,5))!=='%PDF-')throw Error('INVALID_SOURCE_PDF');
  return bytes;
 }catch(error){const timedOut=controller.signal.aborted;controller.abort();if(reader)try{await reader.cancel();}catch{};if(timedOut)throw Error('PDF_DOWNLOAD_TIMEOUT');if((error as Error)?.message?.startsWith('PDF_')||(error as Error)?.message==='INVALID_SOURCE_PDF')throw error;throw Error('PDF_DOWNLOAD_FAILED');}
 finally{clearTimeout(timer);reader?.releaseLock();}
}
