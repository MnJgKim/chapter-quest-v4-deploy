import pg from 'pg';import assert from 'node:assert/strict';import {randomUUID,randomBytes,createHash} from 'node:crypto';import {mkdir,writeFile} from 'node:fs/promises';
import {loadTarget,databaseOptions,needed,api,rpc,isMain,runCli,SafeError,root} from './common.mjs';import {assertInstalled} from './apply.mjs';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
export function pdfFixture(){
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
 const stream='BT /F1 14 Tf 20 260 Td (Chapter Quest isolated integration test) Tj ET';objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
 let pdf='%PDF-1.4\n';const offsets=[0];objects.forEach((object,i)=>{offsets.push(Buffer.byteLength(pdf));pdf+=`${i+1} 0 obj\n${object}\nendobj\n`;});const start=Buffer.byteLength(pdf);pdf+='xref\n0 6\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`;return Buffer.from(pdf);
}
async function denied(response){if(![400,401,403,404].includes(response.status))throw new SafeError('EXPECTED_AUTHORIZATION_DENIAL');}
export async function probe(env=process.env,{model=false}={}){
 const target=await loadTarget(env);needed(env,'CQ_TEST_SUPABASE_ANON_KEY');const service=needed(env,'CQ_TEST_SERVICE_ROLE_KEY');
 const db=new pg.Client(databaseOptions(target,env));await db.connect();const users=[],objects=[],chapters=[];const run=randomUUID(),report={run,status:'running',checks:[],cleanup:'pending'};let phase='database-audit';
 const pass=name=>{report.checks.push({name,status:'passed'});console.log('PASS '+name);};
 const admin=async(path,options={})=>{
  const response=await api(target,env,path,{...options,token:service,headers:{apikey:service,...options.headers}});if(!response.ok)throw new SafeError('ADMIN_TEST_REQUEST_HTTP_'+response.status);return response;
 };
 const call=(token,name,args)=>rpc(target,env,token,name,args);
 const edge=async(token,name,body)=>api(target,env,'/functions/v1/'+name,{token,body,headers:{Origin:target.appOrigin}});
 const edgeOk=async(token,name,body)=>{const r=await edge(token,name,body);if(!r.ok)throw new SafeError('EDGE_'+name.toUpperCase()+'_HTTP_'+r.status);return r.json();};
 async function fixture(label){
  const email=`cq-int-${run}-${label}@example.test`,password=randomBytes(24).toString('base64url');
  const data=await (await admin('/auth/v1/admin/users',{body:{email,password,email_confirm:true}})).json();const id=data.id||data.user?.id;if(!id)throw new SafeError('TEST_USER_ID_MISSING');users.push(id);
  const res=await api(target,env,'/auth/v1/token?grant_type=password',{body:{email,password}});if(!res.ok)throw new SafeError('TEST_AUTH_LOGIN_FAILED');const login=await res.json();if(login.user?.id!==id||!login.refresh_token)throw new SafeError('TEST_AUTH_ID_MISMATCH');return {id,token:login.access_token,refresh:login.refresh_token};
 }
 try{
  await assertInstalled(db,target);
  const audit=(await db.query(`select
   not has_schema_privilege('authenticated','cq_private','USAGE') as private_hidden,
   not has_table_privilege('authenticated','public.cq_v4_chapters','SELECT') as chapter_rest_closed,
   not has_function_privilege('authenticated','public.cq_v4_finalize_pdf(uuid,uuid)','EXECUTE') as finalize_closed,
   not has_function_privilege('anon','public.cq_v4_issue_invite()','EXECUTE') as anon_closed,
   (select bool_and(relrowsecurity) from pg_class where oid in ('public.cq_v4_profiles'::regclass,'public.cq_v4_child_access'::regclass,'public.cq_v4_chapters'::regclass,'public.cq_v4_assignments'::regclass,'public.cq_v4_snapshots'::regclass)) as rls_enabled,
   (select count(*)=2 and bool_and(not public) from storage.buckets where id in ('cq-v4-originals','cq-v4-speaking')) as private_buckets`)).rows[0];
  if(Object.values(audit).some(v=>v!==true))throw new SafeError('DATABASE_SECURITY_AUDIT_FAILED');pass('migration-hashes-rls-grants-private-buckets');
  phase='auth-fixtures';const parent=await fixture('parent'),other=await fixture('other-parent'),student=await fixture('student'),stranger=await fixture('other-student');
  await db.query("update public.cq_v4_profiles set role='parent' where user_id=any($1::uuid[])",[[parent.id,other.id]]);
  assert.equal(await call(student.token,'cq_v4_my_role'),'student');assert.equal(await call(parent.token,'cq_v4_my_role'),'parent');
  const refreshed=await api(target,env,'/auth/v1/token?grant_type=refresh_token',{body:{refresh_token:student.refresh}});if(!refreshed.ok)throw new SafeError('TEST_AUTH_REFRESH_FAILED');const fresh=await refreshed.json();assert.equal(fresh.user.id,student.id);student.token=fresh.access_token;pass('auth-user-trigger-login-refresh-and-parent-bootstrap');
  phase='invite';const code=await call(parent.token,'cq_v4_issue_invite');assert.equal(await call(student.token,'cq_v4_claim_invite',{p_token:code,p_student_name:'Integration student'}),true);
  assert.equal(await call(student.token,'cq_v4_claim_invite',{p_token:code,p_student_name:'Reuse'}),false);assert.deepEqual(await call(student.token,'cq_v4_my_chapters'),[]);
  assert.equal(await call(other.token,'cq_v4_approve_child',{p_child_user_id:student.id}),false);assert.equal(await call(parent.token,'cq_v4_approve_child',{p_child_user_id:student.id}),true);
  await denied(await api(target,env,'/rest/v1/rpc/cq_v4_issue_invite',{token:student.token,body:{}}));await denied(await api(target,env,'/rest/v1/cq_v4_chapters',{token:student.token,method:'GET'}));pass('one-time-invite-parent-approval-and-rest-isolation');
  phase='pdf';const book='cq-int-'+run,localChapter='pdf';const created=await edgeOk(parent.token,'cq-v4-pdf-parent',{action:'create_chapter',book_id:book,chapter_id:localChapter,title:'Integration PDF'});const chapter=created.chapter_uuid;chapters.push(chapter);
  await denied(await edge(other.token,'cq-v4-pdf-parent',{action:'upload_url',chapter_uuid:chapter}));const signed=await edgeOk(parent.token,'cq-v4-pdf-parent',{action:'upload_url',chapter_uuid:chapter});const pdf=pdfFixture();objects.push({bucket:'cq-v4-originals',path:signed.path});
  const upload=await api(target,env,'/storage/v1/object/upload/sign/'+signed.bucket+'/'+signed.path.split('/').map(encodeURIComponent).join('/')+'?token='+encodeURIComponent(signed.token),{method:'PUT',body:pdf,headers:{'Content-Type':'application/pdf'}});if(!upload.ok)throw new SafeError('SIGNED_PDF_UPLOAD_HTTP_'+upload.status);
  assert.equal((await edgeOk(parent.token,'cq-v4-pdf-parent',{action:'finalize_upload',chapter_uuid:chapter})).pdf_ready,true);
  await denied(await api(target,env,'/rest/v1/rpc/cq_v4_finalize_pdf',{token:parent.token,body:{p_chapter_uuid:chapter,p_parent_user_id:parent.id}}));pass('edge-owner-check-signed-upload-byte-verification-service-finalizer');
  const content={p_request_key:randomUUID(),p_book_id:book,p_chapter_id:localChapter,p_title:'Integration PDF',p_source:'A child helps a friend. '.repeat(20),p_questions:[{kind:'inference',text:'Why did the child help?'}],p_answer_key:['To help a friend.'],p_vocabulary:[{word:'friend',meaning:'친구',example:'A kind friend.'}],p_writing_prompt:'Explain.',p_speaking_prompt:'Summarize.'};
  phase='publication';const approval=await call(parent.token,'cq_v4_register_approval_once',content);assert.equal(await call(parent.token,'cq_v4_register_approval_once',content),approval);assert.equal(await call(parent.token,'cq_v4_publish_approved',{p_approval_id:approval,p_children:[student.id]}),chapter);
  assert.equal(await call(parent.token,'cq_v4_publish_approved',{p_approval_id:approval,p_children:[student.id]}),chapter);const assigned=await call(student.token,'cq_v4_my_chapters');assert.equal(assigned[0].chapter_uuid,chapter);assert.equal(JSON.stringify(assigned).includes('answer_key'),false);assert.deepEqual(await call(stranger.token,'cq_v4_my_chapters'),[]);
  const link=await edgeOk(student.token,'cq-v4-pdf-link',{chapter_uuid:chapter});const url=new URL(link.signed_url);if(url.origin!==target.supabaseUrl||!url.pathname.startsWith('/storage/v1/object/sign/cq-v4-originals/'))throw new SafeError('UNTRUSTED_SIGNED_PDF');
  const download=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000)});if(!download.ok)throw new SafeError('SIGNED_PDF_DOWNLOAD_FAILED');assert.equal(hash(new Uint8Array(await download.arrayBuffer())),hash(pdf));await denied(await edge(stranger.token,'cq-v4-pdf-link',{chapter_uuid:chapter}));pass('canonical-uuid-idempotent-publication-pdf-download-and-student-isolation');
  phase='audio-submission';const audioPath=student.id+'/'+chapter+'.webm';objects.push({bucket:'cq-v4-speaking',path:audioPath});const audio=Buffer.from([0x1a,0x45,0xdf,0xa3,0x80]);
  await denied(await api(target,env,'/storage/v1/object/cq-v4-speaking/'+audioPath,{token:stranger.token,body:audio,headers:{'Content-Type':'audio/webm'}}));
  const audioUpload=await api(target,env,'/storage/v1/object/cq-v4-speaking/'+audioPath,{token:student.token,body:audio,headers:{'Content-Type':'audio/webm','x-upsert':'false'}});if(!audioUpload.ok)throw new SafeError('AUDIO_UPLOAD_HTTP_'+audioUpload.status);
  const answers={readComplete:true,answers:['To help a friend.'],essay:'The child was kind.',speaking:'The child helped.',hasAudio:true};assert.equal(await call(student.token,'cq_v4_submit_answers',{p_chapter_uuid:chapter,p_answers:answers}),true);
  await denied(await api(target,env,'/rest/v1/rpc/cq_v4_submit_answers',{token:student.token,body:{p_chapter_uuid:chapter,p_answers:answers}}));
  await call(parent.token,'cq_v4_release_feedback',{p_child_user_id:student.id,p_chapter_uuid:chapter,p_feedback:'Good work',p_release:false});assert.equal((await call(student.token,'cq_v4_my_submission',{p_chapter_uuid:chapter}))[0].feedback,'');await call(parent.token,'cq_v4_release_feedback',{p_child_user_id:student.id,p_chapter_uuid:chapter,p_feedback:'Good work',p_release:true});assert.equal((await call(student.token,'cq_v4_my_submission',{p_chapter_uuid:chapter}))[0].feedback,'Good work');pass('storage-audio-rls-immutable-submission-and-feedback-release');
  phase='text';const text='The original TXT chapter. '.repeat(20);const textId=await call(parent.token,'cq_v4_register_text_chapter',{p_book_id:book,p_chapter_id:'txt',p_title:'Integration TXT',p_text:text});chapters.push(textId);
  await denied(await api(target,env,'/rest/v1/rpc/cq_v4_my_reading',{token:student.token,body:{p_chapter_uuid:textId}}));const textApproval=await call(parent.token,'cq_v4_register_approval_once',{...content,p_request_key:randomUUID(),p_chapter_id:'txt',p_title:'Integration TXT',p_source:text});assert.equal(await call(parent.token,'cq_v4_publish_approved',{p_approval_id:textApproval,p_children:[student.id]}),textId);assert.equal((await call(student.token,'cq_v4_my_reading',{p_chapter_uuid:textId}))[0].reading_text,text);pass('txt-original-approval-assignment-and-reading-rpc');
  phase='revocation';await call(parent.token,'cq_v4_revoke_child',{p_child_user_id:student.id});assert.deepEqual(await call(student.token,'cq_v4_my_chapters'),[]);await denied(await edge(student.token,'cq-v4-pdf-link',{chapter_uuid:chapter}));await denied(await api(target,env,'/rest/v1/rpc/cq_v4_my_reading',{token:student.token,body:{p_chapter_uuid:textId}}));pass('revocation-blocks-new-pdf-links-and-text-access');
  if(env.CQ_TEST_INVITE_EMAIL){phase='mail-invitation';await edgeOk(parent.token,'cq-v4-student-account',{email:env.CQ_TEST_INVITE_EMAIL});pass('account-invitation-request-only');report.checks.push({name:'mail-delivery-password-callback',status:'manual-verification-required'});}else report.checks.push({name:'account-invitation-mail-flow',status:'not-run-controlled-inbox-required'});
  if(model){phase='actual-model';const {modelProbe}=await import('./model.mjs');await modelProbe(target,env,parent.token);pass('actual-model-output-schema');}else report.checks.push({name:'actual-model',status:'not-run-explicit-cost-opt-in-required'});
  report.status='passed';
 }catch(error){report.status='failed';report.failedPhase=phase;report.failureCode=error instanceof SafeError?error.code:typeof error.code==='string'&&/^[A-Z0-9_]+$/.test(error.code)?error.code:'CHECK_FAILED';throw new SafeError('INTEGRATION_PHASE_FAILED_'+phase.toUpperCase());}
 finally{
  // Only this run's known object paths and Auth user UUIDs are deleted. No resets or wildcard deletion.
  try{
   for(const bucket of ['cq-v4-originals','cq-v4-speaking']){const paths=objects.filter(o=>o.bucket===bucket).map(o=>o.path);if(paths.length)await admin('/storage/v1/object/'+bucket,{method:'DELETE',body:{prefixes:paths}});}
   if(users.length){await db.query('begin');await db.query('delete from cq_private.submissions where child_user_id=any($1::uuid[])',[users]);await db.query('delete from public.cq_v4_assignments where child_user_id=any($1::uuid[]) or chapter_uuid in(select chapter_uuid from public.cq_v4_chapters where parent_user_id=any($1::uuid[]))',[users]);await db.query('update public.cq_v4_chapters set approval_id=null where parent_user_id=any($1::uuid[])',[users]);await db.query('delete from cq_private.approvals where parent_user_id=any($1::uuid[])',[users]);await db.query('delete from public.cq_v4_chapters where parent_user_id=any($1::uuid[])',[users]);await db.query('delete from public.cq_v4_child_access where parent_user_id=any($1::uuid[]) or child_user_id=any($1::uuid[])',[users]);await db.query('delete from public.cq_v4_snapshots where owner_id=any($1::uuid[])',[users]);await db.query('delete from cq_private.invites where parent_user_id=any($1::uuid[]) or claimed_by=any($1::uuid[])',[users]);await db.query('delete from cq_private.account_invites where parent_user_id=any($1::uuid[])',[users]);await db.query('commit');for(const id of users)await admin('/auth/v1/admin/users/'+id,{method:'DELETE'});}
   report.cleanup='passed';
  }catch{await db.query('rollback').catch(()=>{});report.cleanup='failed';report.status='failed';report.remainingFixtures={users,chapters,objects};process.exitCode=1;console.error('FIXTURE_CLEANUP_FAILED_SEE_LOCAL_REPORT');}
  await db.end();const folder=new URL('.integration/',root);await mkdir(folder,{recursive:true,mode:0o700});await writeFile(new URL('report-'+run+'.json',folder),JSON.stringify(report,null,2),{mode:0o600});console.log('Report: .integration/report-'+run+'.json');
 }
 return report;
}
if(isMain(import.meta.url))await runCli(async()=>{if(!process.argv.includes('--run'))throw new SafeError('EXPLICIT_RUN_FLAG_REQUIRED');await probe(process.env,{model:process.argv.includes('--allow-model-cost')});});
