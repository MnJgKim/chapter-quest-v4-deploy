import { HttpError, type Gateway, type Json } from './gateway.ts';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export type Endpoint = 'pdf-parent'|'pdf-link'|'student-account';
export function createHandler(endpoint: Endpoint, gateway: Gateway, appOrigin: string, now=()=>Date.now()) {
 const allowedOrigin=new URL(appOrigin).origin;
 return async (req: Request): Promise<Response> => {
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':allowedOrigin,'Vary':'Origin','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
  const reply=(status:number,value:unknown)=>new Response(JSON.stringify(value),{status,headers});
  try {
   if(req.headers.get('Origin') && req.headers.get('Origin')!==allowedOrigin) throw new HttpError(403,'ORIGIN_NOT_ALLOWED');
   if(req.method==='OPTIONS') return new Response(null,{status:204,headers});
   if(req.method!=='POST')throw new HttpError(405,'METHOD_NOT_ALLOWED');
   const token=req.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];if(!token)throw new HttpError(401,'LOGIN_REQUIRED');
   const user=await gateway.user(token);if(!UUID.test(user.id))throw new HttpError(401,'INVALID_USER');
   // Bounded streaming read; Content-Length alone is not trusted.
   const reader=req.body?.getReader();if(!reader)throw new HttpError(400,'INVALID_JSON');
   const chunks:Uint8Array[]=[];let size=0;
   try { while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>8192)throw new HttpError(413,'REQUEST_TOO_LARGE');chunks.push(value);} } finally { await reader.cancel(); }
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   let body:Json;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new HttpError(400,'INVALID_JSON');}
   if(!body || typeof body!=='object' || Array.isArray(body))throw new HttpError(400,'INVALID_JSON');
   const role=await gateway.rpc(token,'cq_v4_my_role');
   if(endpoint==='student-account') {
    if(role!=='parent')throw new HttpError(403,'PARENT_REQUIRED');
    if(typeof body.email!=='string' || body.email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email))throw new HttpError(400,'INVALID_EMAIL');
    // Auth invite sends verification; it does not create an active parent/child relationship.
    await gateway.rpc(token,'cq_v4_reserve_account_invite',{p_email:body.email.trim()});
    await gateway.invite(body.email.trim());return reply(200,{invited:true});
   }
   if(endpoint==='pdf-link') {
    if(role!=='student')throw new HttpError(403,'STUDENT_REQUIRED');
    if(typeof body.chapter_uuid!=='string'||!UUID.test(body.chapter_uuid))throw new HttpError(400,'INVALID_CHAPTER');
    const path=await gateway.rpc(token,'cq_v4_pdf_access',{p_chapter_uuid:body.chapter_uuid});
    if(typeof path!=='string'||!path.endsWith('/'+body.chapter_uuid+'/original.pdf'))throw new HttpError(403,'PDF_ACCESS_DENIED');
    return reply(200,{signed_url:await gateway.signPdf(path),expires_at:new Date(now()+120000).toISOString()});
   }
   if(role!=='parent')throw new HttpError(403,'PARENT_REQUIRED');
   const actions=['list_chapters','list_students','list_assignments','create_chapter','upload_url','finalize_upload','assign','unassign'];
   if(typeof body.action!=='string'||!actions.includes(body.action))throw new HttpError(400,'INVALID_ACTION');
   const {action,...args}=body;
   if(!['list_chapters','list_students','list_assignments','create_chapter'].includes(action) && (typeof args.chapter_uuid!=='string'||!UUID.test(args.chapter_uuid)))throw new HttpError(400,'INVALID_CHAPTER');
   if(action==='finalize_upload') {
    const info=await gateway.rpc(token,'cq_v4_parent_pdf',{p_action:'inspect',p_args:args}) as Json;
    if(typeof info.path!=='string'||info.path!==user.id+'/'+args.chapter_uuid+'/original.pdf')throw new HttpError(403,'PDF_ACCESS_DENIED');
    const header=await gateway.pdfHeader(info.path);
    if(new TextDecoder().decode(header)!=='%PDF-')throw new HttpError(400,'INVALID_PDF_SIGNATURE');
    await gateway.finalize(args.chapter_uuid as string,user.id);return reply(200,{pdf_ready:true});
   }
   const data=await gateway.rpc(token,'cq_v4_parent_pdf',{p_action:action,p_args:args}) as Json;
   if(action==='upload_url') {
    if(typeof data.path!=='string'||data.path!==user.id+'/'+args.chapter_uuid+'/original.pdf')throw new HttpError(403,'PDF_ACCESS_DENIED');
    return reply(200,{...data,...await gateway.uploadUrl(data.path)});
   }
   return reply(200,data);
  } catch(error) { return reply(error instanceof HttpError?error.status:400,{error:error instanceof HttpError?error.message:'REQUEST_FAILED'}); }
 };
}
