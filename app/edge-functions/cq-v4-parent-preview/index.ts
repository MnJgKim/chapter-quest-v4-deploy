// Read-only parent preview of already published Chapter Quest V4 lessons.
// Deploy only after approval; the existing student release gate is unchanged.
import { createClient } from 'npm:@supabase/supabase-js@2';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,'Content-Type':'application/json'}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 if(Number(req.headers.get('content-length')||0)>2048)return reply({error:'REQUEST_TOO_LARGE'},413);
 const authorization=req.headers.get('authorization')||'';
 if(!/^Bearer\s+\S+$/i.test(authorization))return reply({error:'UNAUTHORIZED'},401);
 const url=Deno.env.get('SUPABASE_URL')||'',anon=Deno.env.get('SUPABASE_ANON_KEY')||'',secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
 if(!url||!anon||!secret)return reply({error:'NOT_CONFIGURED'},503);
 let input:{chapter_uuid?:unknown};
 try{const raw=await req.text();if(raw.length>2048)throw Error();input=JSON.parse(raw);if(!input||typeof input!=='object'||Array.isArray(input))throw Error()}catch{return reply({error:'INVALID_JSON'},400)}
 const chapter=input.chapter_uuid;
 if(typeof chapter!=='string'||!uuid.test(chapter))return reply({error:'INVALID_CHAPTER'},400);
 const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
 const {data:identity,error:identityError}=await caller.auth.getUser();
 const parent=identity.user?.id;
 if(identityError||!parent)return reply({error:'UNAUTHORIZED'},401);
 const {data:isAdmin,error:adminError}=await caller.rpc('cq_is_admin');
 if(adminError)return reply({error:'ROLE_CHECK_FAILED'},503);
 if(isAdmin!==true)return reply({error:'PARENT_REQUIRED'},403);
 const admin=createClient(url,secret,{auth:{persistSession:false}});
 const {data:owned,error:chapterError}=await admin.from('cq_v4_pdf_chapters').select('chapter_id,title,storage_path,pdf_ready').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle();
 if(chapterError)return reply({error:'LOOKUP_FAILED'},503);
 if(!owned)return reply({error:'FORBIDDEN'},403);
 if(!owned.pdf_ready||owned.storage_path!==parent+'/'+chapter+'.pdf')return reply({error:'PDF_NOT_VERIFIED'},409);
 const {data:activity,error:activityError}=await admin.from('cq_v4_activities').select('questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id,approval_hash').eq('chapter_uuid',chapter).maybeSingle();
 if(activityError)return reply({error:'ACTIVITY_LOOKUP_FAILED'},503);
 if(!activity?.published_at)return reply({error:'NOT_PUBLISHED'},404);
 const {data:signed,error:signError}=await admin.storage.from('cq-v4-originals').createSignedUrl(owned.storage_path,120);
 if(signError||!signed?.signedUrl)return reply({error:'PDF_LINK_FAILED'},503);
 const link=new URL(signed.signedUrl,url);
 if(link.origin!==new URL(url).origin||!link.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/')||!link.searchParams.has('token'))return reply({error:'INVALID_SIGNED_URL'},503);
 return reply({chapter_uuid:chapter,title:owned.title,questions:activity.questions,vocabulary:activity.vocabulary,writing_prompt:activity.writing_prompt,speaking_prompt:activity.speaking_prompt,approval_id:activity.approval_id,approval_hash:activity.approval_hash,published_at:activity.published_at,signed_url:link.href,expires_at:new Date(Date.now()+120000).toISOString()});
});
