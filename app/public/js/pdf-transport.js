/* Chapter Quest V4: authenticated, fail-closed server PDF transport.
   Backend Edge Function cq-v4-pdf-link must enforce student assignment and return
   {signed_url, expires_at}. No browser-side access check is a substitute for RLS. */
(function(root){
  function createPdfTransport({url,anonKey,getAccessToken,fetchImpl=fetch,now=()=>Date.now()}){
    if(!(globalThis.CQOrigin?.allows(url||'')??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url||'')))throw Error('INVALID_SUPABASE_ORIGIN');
    if(!anonKey||typeof getAccessToken!=='function'||typeof fetchImpl!=='function')throw Error('INVALID_PDF_TRANSPORT_CONFIG');
    async function getPdf(chapterUuid,{signal}={}){
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(chapterUuid||''))throw Error('INVALID_CHAPTER_UUID');
      if(signal?.aborted)throw Error('PDF_REQUEST_CANCELLED');
      const token=await getAccessToken();
      if(!token)throw Error('STUDENT_LOGIN_REQUIRED');
      const rpcResponse=await fetchImpl(url+'/functions/v1/cq-v4-pdf-link',{
        method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},
        body:JSON.stringify({chapter_uuid:chapterUuid}),signal
      });
      if(!rpcResponse.ok)throw Error('PDF_ACCESS_DENIED_OR_UNAVAILABLE');
      const payload=await rpcResponse.json();
      const link=Array.isArray(payload)?payload[0]:payload;
      if(!link?.signed_url||!link?.expires_at)throw Error('PDF_LINK_NOT_AVAILABLE');
      const signed=new URL(link.signed_url,url);
      const base=new URL(url);
      if(signed.origin!==base.origin||!signed.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/'))throw Error('UNTRUSTED_PDF_URL');
      if(!signed.searchParams.has('token'))throw Error('UNSIGNED_PDF_URL');
      const expires=Date.parse(link.expires_at);
      if(!Number.isFinite(expires)||expires<=now()+5000||expires>now()+10*60*1000)throw Error('INVALID_PDF_LINK_EXPIRY');
      if(signal?.aborted)throw Error('PDF_REQUEST_CANCELLED');
      const response=await fetchImpl(signed.toString(),{method:'GET',signal,headers:{apikey:anonKey,Authorization:'Bearer '+token}});
      if(!response.ok)throw Error('PDF_DOWNLOAD_FAILED');
      const type=(response.headers?.get('content-type')||'').toLowerCase();
      if(type&&!type.includes('application/pdf')&&!type.includes('octet-stream'))throw Error('INVALID_PDF_CONTENT_TYPE');
      // Reject oversized responses before allocating, then enforce the same limit while streaming.
      const maxPdfBytes=50*1024*1024;
      const declaredLength=response.headers?.get('content-length');
      if(declaredLength!==null&&declaredLength!==undefined&&declaredLength!==''){
        const declared=Number(declaredLength);
        if(!Number.isSafeInteger(declared)||declared<5||declared>maxPdfBytes)throw Error('INVALID_PDF_SIZE');
      }
      let bytes;
      if(response.body&&typeof response.body.getReader==='function'){
        const reader=response.body.getReader(),chunks=[];
        let total=0;
        try{
          while(true){
            if(signal?.aborted)throw Error('PDF_REQUEST_CANCELLED');
            const {done,value}=await reader.read();
            if(done)break;
            if(!(value instanceof Uint8Array))throw Error('INVALID_PDF_STREAM');
            total+=value.byteLength;
            if(total>maxPdfBytes)throw Error('INVALID_PDF_SIZE');
            chunks.push(value);
          }
        }catch(error){try{await reader.cancel()}catch{}throw error}
        if(total<5)throw Error('INVALID_PDF_SIZE');
        const merged=new Uint8Array(total);
        let offset=0;
        for(const chunk of chunks){merged.set(chunk,offset);offset+=chunk.byteLength}
        bytes=merged.buffer;
      }else{
        bytes=await response.arrayBuffer();
        if(bytes.byteLength<5||bytes.byteLength>maxPdfBytes)throw Error('INVALID_PDF_SIZE');
      }
      const header=new Uint8Array(bytes,0,5);
      if(String.fromCharCode(...header)!=='%PDF-')throw Error('INVALID_PDF_SIGNATURE');
      if(signal?.aborted)throw Error('PDF_REQUEST_CANCELLED');
      return bytes;
    }
    return Object.freeze({getPdf});
  }
  root.CQServerPDF=Object.freeze({createPdfTransport});
  if(typeof module!=='undefined'&&module.exports)module.exports={createPdfTransport};
})(typeof window!=='undefined'?window:globalThis);
