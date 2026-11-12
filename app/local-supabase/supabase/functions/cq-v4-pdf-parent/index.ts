// Supabase Edge Function: cq-v4-pdf-parent
// Parent-only PDF chapter creation, signed upload issuance, and assignment.
// Requires JWT verification enabled at the function gateway.
import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import { derivePdfRange } from '../_shared/pdf-range.ts';
import { downloadPdfBytes } from '../_shared/pdf-download.ts';
const validPdfPath=(path:unknown,parent:string,chapter:string)=>typeof path==='string'&&path===`${parent}/${chapter}.pdf`;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return respond({error:'METHOD_NOT_ALLOWED'},405);
  if(Number(req.headers.get('content-length')||0)>8192)return respond({error:'REQUEST_TOO_LARGE'},413);
  const auth=req.headers.get('authorization')||'';
  if(!/^Bearer\s+\S+$/i.test(auth))return respond({error:'UNAUTHORIZED'},401);
  const url=Deno.env.get('SUPABASE_URL')||'',anon=Deno.env.get('SUPABASE_ANON_KEY')||'',service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
  if(!url||!anon||!service)return respond({error:'SERVER_NOT_CONFIGURED'},503);
  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:identity,error:identityError}=await caller.auth.getUser();
  const parent=identity.user?.id;
  if(identityError||!parent)return respond({error:'UNAUTHORIZED'},401);
  let input:Record<string,unknown>;
  try{const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return respond({error:'REQUEST_TOO_LARGE'},413);const value=JSON.parse(raw);if(!value||typeof value!=='object'||Array.isArray(value))throw Error();input=value;}
  catch{return respond({error:'INVALID_JSON'},400)}
  // Authenticate and authorize before constructing a privileged service-role client.
  const {data:isParent,error:roleError}=await caller.rpc('cq_is_admin');
  if(roleError)return respond({error:'PARENT_ACCESS_CHECK_FAILED'},503);
  if(isParent!==true)return respond({error:'PARENT_REQUIRED'},403);
  const admin=createClient(url,service,{auth:{persistSession:false}});
  if(input.action==='create_range'){
    const source=input.source_uuid,request=input.request_key,start=input.page_start,end=input.page_end,title=input.title,expected=input.source_sha256;
    if(typeof source!=='string'||!uuid.test(source)||typeof request!=='string'||!uuid.test(request)||typeof title!=='string'||!title.trim()||title.length>200||!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||Number(start)<1||Number(end)<Number(start)||typeof expected!=='string'||!/^[0-9a-f]{64}$/.test(expected))return respond({error:'INVALID_RANGE_REQUEST'},400);
    const {data:owned,error:ownerError}=await admin.from('cq_v4_pdf_chapters').select('storage_path,pdf_ready').eq('chapter_id',source).eq('parent_user_id',parent).maybeSingle();
    if(ownerError)return respond({error:'SOURCE_ACCESS_CHECK_FAILED'},503);
    if(!owned?.pdf_ready||!validPdfPath(owned.storage_path,parent,source))return respond({error:'VERIFIED_OWNED_SOURCE_REQUIRED'},403);
    const {data:prior,error:priorError}=await admin.from('cq_v4_pdf_page_ranges').select('*').eq('parent_user_id',parent).eq('request_key',request).maybeSingle();
    if(priorError)return respond({error:'RANGE_REGISTRY_UNAVAILABLE'},503);
    if(prior){if(prior.source_pdf_uuid!==source||prior.page_start!==start||prior.page_end!==end||prior.title!==title.trim()||prior.source_sha256!==expected)return respond({error:'RANGE_REQUEST_CONFLICT'},409);return respond({chapter_uuid:prior.derived_pdf_uuid,pdf_ready:true,page_count:prior.page_end-prior.page_start+1,server_verified_range:true});}
    let bytes;try{bytes=await downloadPdfBytes(url,service,owned.storage_path);}catch{return respond({error:'SOURCE_DOWNLOAD_FAILED'},503);}
    let derived;try{derived=await derivePdfRange(bytes,Number(start),Number(end),title.trim());}catch{return respond({error:'INVALID_SOURCE_OR_PAGE_RANGE'},400);}
    if(derived.source_sha256!==expected)return respond({error:'SOURCE_CHANGED_SINCE_PREVIEW'},409);
    const reuseOriginal=start===1&&end===derived.source_page_count;
    const id=reuseOriginal?source:crypto.randomUUID(),path=`${parent}/${id}.pdf`;
    const {error:uploadError}=reuseOriginal?{error:null}:await admin.storage.from('cq-v4-originals').upload(path,derived.bytes,{contentType:'application/pdf',upsert:false});
    if(uploadError)return respond({error:'DERIVED_UPLOAD_FAILED'},503);
    const {data:committed,error:commitError}=await admin.rpc('cq_v4_commit_pdf_range',{p_parent:parent,p_request:request,p_source:source,p_derived:id,p_start:start,p_end:end,p_total:derived.source_page_count,p_title:title.trim(),p_source_sha:derived.source_sha256,p_derived_sha:derived.derived_sha256});
    if(commitError||typeof committed!=='string'){if(!reuseOriginal)await admin.storage.from('cq-v4-originals').remove([path]);return respond({error:'RANGE_COMMIT_FAILED'},503);}
    if(!reuseOriginal&&committed!==id)await admin.storage.from('cq-v4-originals').remove([path]);
    return respond({chapter_uuid:committed,pdf_ready:true,page_count:derived.page_count,server_verified_range:true});
  }
  if(input.action==='list_chapters'){
    const {data,error}=await admin.from('cq_v4_pdf_chapters').select('chapter_id,title,pdf_ready,created_at').eq('parent_user_id',parent).order('created_at',{ascending:false}).limit(201);
    if(error)return respond({error:'CHAPTER_LIST_FAILED'},503);
    if((data||[]).length>200)return respond({error:'CHAPTER_LIST_LIMIT'},409);
    return respond({chapters:(data||[]).map(c=>({chapter_uuid:c.chapter_id,title:c.title,pdf_ready:c.pdf_ready}))});
  }
  if(input.action==='list_students'){
    const {data,error}=await admin.from('cq_v4_pdf_enrollments').select('student_user_id').eq('parent_user_id',parent).limit(201);
    if(error)return respond({error:'STUDENT_LIST_FAILED'},503);
    if((data||[]).length>200)return respond({error:'STUDENT_LIST_LIMIT'},409);
    return respond({students:(data||[]).map(c=>({student_user_id:c.student_user_id}))});
  }
  if(input.action==='list_assignments'){
    const {data:chapters,error:chapterError}=await admin.from('cq_v4_pdf_chapters').select('chapter_id').eq('parent_user_id',parent).limit(201);
    if(chapterError)return respond({error:'CHAPTER_LIST_FAILED'},503);
    if((chapters||[]).length>200)return respond({error:'CHAPTER_LIST_LIMIT'},409);
    const ids=(chapters||[]).map(c=>c.chapter_id);
    if(!ids.length)return respond({assignments:[]});
    const {data:rows,error:assignmentError}=await admin.from('cq_v4_pdf_assignments').select('chapter_id,student_user_id').in('chapter_id',ids).limit(5001);
    if(assignmentError)return respond({error:'ASSIGNMENT_LIST_FAILED'},503);
    if((rows||[]).length>5000)return respond({error:'ASSIGNMENT_LIST_LIMIT'},409);
    // Exclude revoked parent/student links even when an old assignment row remains.
    const {data:enrollments,error:enrollmentError}=await admin.from('cq_v4_pdf_enrollments').select('student_user_id').eq('parent_user_id',parent).limit(5001);
    if(enrollmentError)return respond({error:'ENROLLMENT_LIST_FAILED'},503);
    if((enrollments||[]).length>5000)return respond({error:'ENROLLMENT_LIST_LIMIT'},409);
    const active=new Set((enrollments||[]).map(e=>e.student_user_id));
    return respond({assignments:(rows||[]).filter(r=>active.has(r.student_user_id)).map(r=>({chapter_uuid:r.chapter_id,student_user_id:r.student_user_id}))});
  }
  if(input.action==='create_chapter'){
    const title=input.title;
    if(typeof title!=='string'||title.trim().length<1||title.trim().length>200)return respond({error:'INVALID_TITLE'},400);
    const chapter=crypto.randomUUID(),path=`${parent}/${chapter}.pdf`;
    const {error}=await admin.from('cq_v4_pdf_chapters').insert({chapter_id:chapter,parent_user_id:parent,title:title.trim(),storage_path:path});
    if(error)return respond({error:'CREATE_FAILED'},503);
    return respond({chapter_uuid:chapter});
  }
  if(input.action==='audio_download_url'){
    const chapter=input.chapter_uuid,student=input.student_user_id;
    if(typeof chapter!=='string'||!uuid.test(chapter)||typeof student!=='string'||!uuid.test(student))return respond({error:'INVALID_RECORDING'},400);
    // Reuse the existing caller-JWT RPC: ownership, current assignment, enrollment and
    // final submission are authoritative here. Do not broaden Storage/table policies.
    const {data:submitted,error:accessError}=await caller.rpc('cq_v4_parent_submissions').eq('chapter_uuid',chapter).eq('child_user_id',student).maybeSingle();
    if(accessError)return respond({error:'RECORDING_ACCESS_CHECK_FAILED'},503);
    if(!submitted?.submitted_at||submitted.answers?.hasAudio!==true)return respond({error:'FORBIDDEN'},403);
    for(const ext of ['webm','mp4','ogg']){
      const path=`${student}/${chapter}.${ext}`;
      const {data:link,error}=await admin.storage.from('cq-v4-speaking').createSignedUrl(path,120);
      if(error||!link?.signedUrl)continue;
      const signed=new URL(link.signedUrl,url);
      if(signed.origin!==new URL(url).origin||signed.pathname!==`/storage/v1/object/sign/cq-v4-speaking/${path}`||!signed.searchParams.has('token'))return respond({error:'INVALID_SIGNED_LINK'},500);
      return respond({signed_url:signed.pathname+signed.search,expires_at:new Date(Date.now()+120000).toISOString()});
    }
    return respond({error:'RECORDING_NOT_AVAILABLE'},404);
  }
  if(input.action==='download_url'){
    const chapter=input.chapter_uuid;
    if(typeof chapter!=='string'||!uuid.test(chapter))return respond({error:'INVALID_CHAPTER'},400);
    const {data:owned,error:ownerError}=await admin.from('cq_v4_pdf_chapters').select('storage_path,pdf_ready').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle();
    if(ownerError)return respond({error:'ACCESS_CHECK_FAILED'},503);
    if(!owned)return respond({error:'FORBIDDEN'},403);
    if(!owned.pdf_ready||!validPdfPath(owned.storage_path,parent,chapter))return respond({error:'VERIFIED_PDF_REQUIRED'},409);
    const {data:link,error}=await admin.storage.from('cq-v4-originals').createSignedUrl(owned.storage_path,120);
    if(error||!link?.signedUrl)return respond({error:'PDF_DOWNLOAD_LINK_FAILED'},503);
    const signed=new URL(link.signedUrl,url);
    if(signed.origin!==new URL(url).origin||!signed.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/'))return respond({error:'INVALID_SIGNED_LINK'},500);
    return respond({signed_url:signed.pathname+signed.search,expires_at:new Date(Date.now()+120000).toISOString()});
  }
  if(input.action==='upload_url'){
    const chapter=input.chapter_uuid;
    if(typeof chapter!=='string'||!uuid.test(chapter))return respond({error:'INVALID_CHAPTER'},400);
    const {data:owned,error:ownerError}=await admin.from('cq_v4_pdf_chapters').select('storage_path,pdf_ready').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle();
    if(ownerError)return respond({error:'ACCESS_CHECK_FAILED'},503);
    if(!owned)return respond({error:'FORBIDDEN'},403);
    if(!validPdfPath(owned.storage_path,parent,chapter))return respond({error:'INVALID_STORAGE_PATH'},409);
    // Do not mint new tokens for verified PDFs. Previously issued tokens may remain valid.
    if(owned.pdf_ready)return respond({error:'PDF_ALREADY_VERIFIED'},409);
    const {data:upload,error}=await admin.storage.from('cq-v4-originals').createSignedUploadUrl(owned.storage_path);
    if(error||!upload?.token)return respond({error:'UPLOAD_LINK_FAILED'},503);
    // Token and path are used only with the Supabase signed-upload API.
    return respond({path:owned.storage_path,token:upload.token,bucket:'cq-v4-originals'});
  }
  if(input.action==='finalize_upload'){
    const chapter=input.chapter_uuid;
    if(typeof chapter!=='string'||!uuid.test(chapter))return respond({error:'INVALID_CHAPTER'},400);
    const {data:owned,error:ownerError}=await admin.from('cq_v4_pdf_chapters').select('storage_path,pdf_ready').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle();
    if(ownerError)return respond({error:'ACCESS_CHECK_FAILED'},503);
    if(!owned)return respond({error:'FORBIDDEN'},403);
    if(!validPdfPath(owned.storage_path,parent,chapter))return respond({error:'INVALID_STORAGE_PATH'},409);
    if(owned.pdf_ready)return respond({pdf_ready:true,already_verified:true});
    // Verify the actual storage object before allowing assignment or student access.
    const {data:objects,error:listError}=await admin.storage.from('cq-v4-originals').list(parent,{search:chapter+'.pdf',limit:10});
    if(listError)return respond({error:'UPLOAD_CHECK_FAILED'},503);
    const object=objects?.find(x=>x.name===chapter+'.pdf');
    const size=Number(object?.metadata?.size);
    const mime=String(object?.metadata?.mimetype||'').toLowerCase();
    if(!object||!Number.isFinite(size)||size<5||size>50*1024*1024||mime!=='application/pdf')return respond({error:'PDF_NOT_VERIFIED'},409);
    const {data:verifiedFile,error:downloadError}=await admin.storage.from('cq-v4-originals').download(owned.storage_path);
    if(downloadError||!verifiedFile)return respond({error:'PDF_DOWNLOAD_CHECK_FAILED'},503);
    const bytes=new Uint8Array(await verifiedFile.slice(0,5).arrayBuffer());
    if(bytes.length!==5||String.fromCharCode(...bytes)!=='%PDF-')return respond({error:'INVALID_PDF_SIGNATURE'},409);
    const {data:updated,error:updateError}=await admin.from('cq_v4_pdf_chapters').update({pdf_ready:true,pdf_verified_at:new Date().toISOString()}).eq('chapter_id',chapter).eq('parent_user_id',parent).eq('storage_path',owned.storage_path).eq('pdf_ready',false).select('chapter_id');
    if(updateError)return respond({error:'VERIFY_SAVE_FAILED'},503);
    if(!updated?.length)return respond({error:'VERIFICATION_RACE_RETRY'},409);
    return respond({pdf_ready:true});
  }
  if(input.action==='assign'){
    const chapter=input.chapter_uuid,student=input.student_user_id;
    if(typeof chapter!=='string'||!uuid.test(chapter)||typeof student!=='string'||!uuid.test(student))return respond({error:'INVALID_ASSIGNMENT'},400);
    const [{data:owned,error:ownerError},{data:enrolled,error:enrollmentError}]=await Promise.all([
      admin.from('cq_v4_pdf_chapters').select('chapter_id,pdf_ready').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle(),
      admin.from('cq_v4_pdf_enrollments').select('student_user_id').eq('parent_user_id',parent).eq('student_user_id',student).maybeSingle()
    ]);
    if(ownerError||enrollmentError)return respond({error:'ACCESS_CHECK_FAILED'},503);
    if(!owned||!enrolled)return respond({error:'FORBIDDEN'},403);
    if(!owned.pdf_ready)return respond({error:'PDF_NOT_VERIFIED'},409);
    const {data:published,error:publishedError}=await admin.from('cq_v4_activities').select('approval_id,approval_hash,published_at').eq('chapter_uuid',chapter).maybeSingle();
    if(publishedError)return respond({error:'PUBLICATION_CHECK_FAILED'},503);
    if(!published?.published_at||!published.approval_id||typeof published.approval_hash!=='string'||!published.approval_hash)return respond({error:'APPROVED_PUBLICATION_REQUIRED'},403);
    const {data:approved,error:approvalError}=await admin.from('cq_v4_approval_requests').select('chapter_uuid,parent_user_id,content_hash').eq('id',published.approval_id).maybeSingle();
    if(approvalError)return respond({error:'APPROVAL_CHECK_FAILED'},503);
    if(!approved||approved.parent_user_id!==parent||approved.chapter_uuid!==chapter||approved.content_hash!==published.approval_hash)return respond({error:'APPROVED_PUBLICATION_REQUIRED'},403);
    const {error}=await admin.from('cq_v4_pdf_assignments').upsert({chapter_id:chapter,student_user_id:student},{onConflict:'chapter_id,student_user_id'});
    if(error)return respond({error:'ASSIGN_FAILED'},503);
    return respond({assigned:true});
  }
  if(input.action==='unassign'){
    const chapter=input.chapter_uuid,student=input.student_user_id;
    if(typeof chapter!=='string'||!uuid.test(chapter)||typeof student!=='string'||!uuid.test(student))return respond({error:'INVALID_ASSIGNMENT'},400);
    const {data:owned,error:ownerError}=await admin.from('cq_v4_pdf_chapters').select('chapter_id').eq('chapter_id',chapter).eq('parent_user_id',parent).maybeSingle();
    if(ownerError)return respond({error:'ACCESS_CHECK_FAILED'},503);
    if(!owned)return respond({error:'FORBIDDEN'},403);
    const {error}=await admin.from('cq_v4_pdf_assignments').delete().eq('chapter_id',chapter).eq('student_user_id',student);
    if(error)return respond({error:'UNASSIGN_FAILED'},503);
    return respond({unassigned:true});
  }
  return respond({error:'INVALID_ACTION'},400);
});
