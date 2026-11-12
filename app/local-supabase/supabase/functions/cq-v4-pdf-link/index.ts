// Supabase Edge Function: cq-v4-pdf-link
// Requires SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import { pdfSha256 } from '../_shared/pdf-range.ts';
const validPdfPath=(path:unknown,parent:string,chapter:string)=>typeof path==='string'&&path===`${parent}/${chapter}.pdf`;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return json({error:'METHOD_NOT_ALLOWED'},405);
  if(Number(req.headers.get('content-length')||0)>8192)return json({error:'REQUEST_TOO_LARGE'},413);
  const auth=req.headers.get('authorization')||'';
  if(!/^Bearer\s+\S+$/i.test(auth))return json({error:'UNAUTHORIZED'},401);
  const url=Deno.env.get('SUPABASE_URL')||'';
  const anon=Deno.env.get('SUPABASE_ANON_KEY')||'';
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
  if(!url||!anon||!service)return json({error:'SERVER_NOT_CONFIGURED'},503);
  let input:unknown;
  try{const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return json({error:'REQUEST_TOO_LARGE'},413);input=JSON.parse(raw)}catch{return json({error:'INVALID_JSON'},400)}
  const chapter=(input as {chapter_uuid?:unknown})?.chapter_uuid;
  if(typeof chapter!=='string'||!uuid.test(chapter))return json({error:'INVALID_CHAPTER'},400);
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:userData,error:userError}=await userClient.auth.getUser();
  const userId=userData.user?.id;
  if(userError||!userId)return json({error:'UNAUTHORIZED'},401);
  // All access checks use the user's JWT and RLS; no service-role query for authorization.
  const {data:assignment,error:assignmentError}=await userClient.from('cq_v4_pdf_assignments').select('chapter_id').eq('chapter_id',chapter).eq('student_user_id',userId).maybeSingle();
  if(assignmentError)return json({error:'ACCESS_CHECK_FAILED'},503);
  if(!assignment)return json({error:'FORBIDDEN'},403);
  const {data:chapterRow,error:chapterError}=await userClient.from('cq_v4_pdf_chapters').select('storage_path,pdf_ready,parent_user_id').eq('chapter_id',chapter).maybeSingle();
  if(chapterError||!chapterRow||!chapterRow.pdf_ready)return json({error:'PDF_NOT_AVAILABLE'},404);
  if(!validPdfPath(chapterRow.storage_path,chapterRow.parent_user_id,chapter))return json({error:'INVALID_STORAGE_PATH'},409);
  // Revoking a parent-child enrollment also revokes newly issued PDF links.
  const {data:enrollment,error:enrollmentError}=await userClient.from('cq_v4_pdf_enrollments').select('student_user_id').eq('parent_user_id',chapterRow.parent_user_id).eq('student_user_id',userId).maybeSingle();
  if(enrollmentError)return json({error:'ACCESS_CHECK_FAILED'},503);
  if(!enrollment)return json({error:'FORBIDDEN'},403);
  const {data:activities,error:activityError}=await userClient.rpc('cq_v4_my_chapter_activities',{p_chapter_uuid:chapter});
  if(activityError||!Array.isArray(activities)||activities.length!==1)return json({error:'PUBLISHED_LESSON_REQUIRED'},403);
  const admin=createClient(url,service,{auth:{persistSession:false}});
  const {data:range,error:rangeError}=await admin.from('cq_v4_pdf_page_ranges').select('*').eq('derived_pdf_uuid',chapter).maybeSingle();
  if(rangeError)return json({error:'RANGE_ACCESS_CHECK_FAILED'},503);
  let pageCount=null;
  if(range){
    if(range.parent_user_id!==chapterRow.parent_user_id||(range.derived_pdf_uuid===range.source_pdf_uuid&&(range.page_start!==1||range.page_end!==range.source_page_count||range.source_sha256!==range.derived_sha256))||!Number.isSafeInteger(range.page_start)||!Number.isSafeInteger(range.page_end)||range.page_start<1||range.page_end<range.page_start||range.page_end>range.source_page_count)return json({error:'INVALID_VERIFIED_RANGE'},403);
    const {data:published,error:publishedError}=await admin.from('cq_v4_activities').select('approval_id').eq('chapter_uuid',chapter).maybeSingle();
    const {data:approved,error:approvedError}=await admin.from('cq_v4_approval_requests').select('chapter_uuid,parent_user_id').eq('id',published?.approval_id).maybeSingle();
    if(publishedError||approvedError||approved?.chapter_uuid!==chapter||approved?.parent_user_id!==chapterRow.parent_user_id)return json({error:'APPROVED_RANGE_REQUIRED'},403);
    const {data:file,error:fileError}=await admin.storage.from('cq-v4-originals').download(chapterRow.storage_path);
    if(fileError||!file||file.size>50*1024*1024||await pdfSha256(new Uint8Array(await file.arrayBuffer()))!==range.derived_sha256)return json({error:'DERIVED_PDF_INTEGRITY_FAILED'},403);
    pageCount=range.page_end-range.page_start+1;
  }
  const {data:link,error:signError}=await admin.storage.from('cq-v4-originals').createSignedUrl(chapterRow.storage_path,120);
  if(signError||!link?.signedUrl)return json({error:'PDF_NOT_AVAILABLE'},404);
  const signed=new URL(link.signedUrl,url);
  if(signed.origin!==new URL(url).origin||!signed.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/'))return json({error:'INVALID_SIGNED_LINK'},500);
  return json({signed_url:signed.pathname+signed.search,expires_at:new Date(Date.now()+120000).toISOString(),...(pageCount?{page_count:pageCount}:{} )});
});
