export type Config = { url: string; anonKey: string; serviceKey: string; origin: string };
export type Json = Record<string, unknown>;
export class HttpError extends Error { status: number; constructor(status: number, message: string) { super(message); this.status=status; } }
export interface Gateway {
 user(token: string): Promise<{id: string}>;
 rpc(token: string, name: string, args?: Json): Promise<unknown>;
 uploadUrl(path: string): Promise<{token: string}>;
 pdfHeader(path: string): Promise<Uint8Array>;
 finalize(chapter: string, parent: string): Promise<unknown>;
 signPdf(path: string): Promise<string>;
 invite(email: string): Promise<void>;
}
export function createGateway(config: Config, fetcher: typeof fetch = fetch): Gateway {
 const base = config.url.replace(/\/$/, '');
 if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(base) && !/^http:\/\/(localhost|127\.0\.0\.1|kong):[0-9]+$/.test(base)) throw new Error('INVALID_SERVER_URL');
 const path = (value: string) => value.split('/').map(encodeURIComponent).join('/');
 async function request(route: string, token: string, body?: unknown, method = 'POST') {
  const res = await fetcher(base + route, { method, headers: {apikey: config.anonKey, Authorization: `Bearer ${token}`, 'Content-Type':'application/json'}, ...(body === undefined ? {} : {body:JSON.stringify(body)}), redirect:'error' });
  if (!res.ok) throw new HttpError(res.status === 401 || res.status === 403 ? res.status : 400, 'UPSTREAM_REQUEST_FAILED');
  return res.json();
 }
 async function service(route: string, body: unknown) {
  const res = await fetcher(base + route, { method:'POST', headers:{apikey:config.serviceKey,Authorization:`Bearer ${config.serviceKey}`,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'error'});
  if (!res.ok) throw new HttpError(400,'SERVICE_REQUEST_FAILED');
  return res.json();
 }
 return {
  user: token => request('/auth/v1/user', token, undefined, 'GET'),
  rpc: (token,name,args={}) => request('/rest/v1/rpc/'+name,token,args),
  uploadUrl: object => service('/storage/v1/object/upload/sign/cq-v4-originals/'+path(object), {upsert:false}),
  async pdfHeader(object) {
   const res = await fetcher(base+'/storage/v1/object/authenticated/cq-v4-originals/'+path(object), {headers:{apikey:config.serviceKey,Authorization:`Bearer ${config.serviceKey}`,Range:'bytes=0-4'},redirect:'error'});
   if (!res.ok || !res.body) throw new HttpError(400,'PDF_DOWNLOAD_FAILED');
   const reader=res.body.getReader(); const head=new Uint8Array(5);let size=0;
   try { while(size<5) { const {done,value}=await reader.read(); if(done)break; const part=value.subarray(0,5-size);head.set(part,size);size+=part.length; } } finally { await reader.cancel(); }
   if(size!==5)throw new HttpError(400,'INVALID_PDF');return head;
  },
  finalize: (chapter,parent) => service('/rest/v1/rpc/cq_v4_finalize_pdf',{p_chapter_uuid:chapter,p_parent_user_id:parent}),
  async signPdf(object) { const data=await service('/storage/v1/object/sign/cq-v4-originals/'+path(object),{expiresIn:120}); const signed=String(data.signedURL||'');
   const result=new URL(signed.startsWith('/object/')?base+'/storage/v1'+signed:signed,base);
   if(result.origin!==new URL(base).origin||!result.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/')||!result.searchParams.has('token'))throw new HttpError(400,'INVALID_SIGNED_URL');
   return result.href; },
  async invite(email) { await service('/auth/v1/invite?redirect_to='+encodeURIComponent(config.origin+'/'),{email}); }
 };
}
