import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
const db=new PGlite();
const parent='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222',student='33333333-3333-4333-8333-333333333333',stranger='44444444-4444-4444-8444-444444444444';
async function sql(q,args=[]){return (await db.query(q,args)).rows;}
async function as(uid,role='authenticated'){await db.exec('reset role');await sql("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec('set role '+role);}
async function rpc(name,args={}){const values=Object.values(args);const named=Object.keys(args).map((k,i)=>`${k} => $${i+1}`).join(',');return (await sql(`select public.${name}(${named}) as result`,values))[0].result;}
const material={p_request_key:'55555555-5555-4555-8555-555555555555',p_book_id:'book-local',p_chapter_id:'chapter-local',p_title:'Chapter 1',p_source:'Test source',p_questions:JSON.stringify([{kind:'mc',text:'What?',options:['A','B']}]),p_answer_key:'[0]',p_vocabulary:'[{"word":"test","meaning":"시험"}]',p_writing_prompt:'Write',p_speaking_prompt:'Speak'};
let chapter,approval,invite;
before(async()=>{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated,anon,service_role;grant execute on function auth.uid() to authenticated,anon,service_role;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,update,delete on storage.objects to authenticated;`);
 for(const file of (await readdir(new URL('../supabase/migrations/',import.meta.url))).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
 await sql('insert into auth.users values($1),($2),($3),($4)',[parent,other,student,stranger]);await sql("update public.cq_v4_profiles set role='parent' where user_id in ($1,$2)",[parent,other]);
});
after(()=>db.close());
test('signup trigger creates students; students cannot elevate roles or call parent RPC',async()=>{await as(student);assert.equal(await rpc('cq_v4_my_role'),'student');await assert.rejects(sql("update public.cq_v4_profiles set role='parent'"),/permission denied/);await assert.rejects(rpc('cq_v4_issue_invite'),/FORBIDDEN/);});
test('anonymous callers cannot issue invites',async()=>{await as('', 'anon');await assert.rejects(rpc('cq_v4_issue_invite'),/permission denied/);});
test('invite is single-use; claim does not activate; only owning parent may approve',async()=>{
 await as(parent);invite=await rpc('cq_v4_issue_invite');assert.match(invite,/^[a-f0-9]{48}$/);
 await as(student);assert.equal(await rpc('cq_v4_claim_invite',{p_token:invite,p_student_name:'Student'}),true);assert.equal(await rpc('cq_v4_claim_invite',{p_token:invite,p_student_name:'Again'}),false);
 assert.deepEqual(await sql('select * from public.cq_v4_my_chapters()'),[]); // set-returning RPC is queried separately below
 await as(other);assert.equal(await rpc('cq_v4_approve_child',{p_child_user_id:student}),false);assert.deepEqual(await sql('select * from public.cq_v4_child_access'),[]);
 await as(parent);assert.equal((await sql('select active from public.cq_v4_child_access'))[0].active,false);assert.equal(await rpc('cq_v4_approve_child',{p_child_user_id:student}),true);
});
test('expired invite cannot be used',async()=>{await as(parent);const token=await rpc('cq_v4_issue_invite');await as(parent,'postgres');await sql("update cq_private.invites set expires_at=now()-interval '1 second' where token_hash=sha256(convert_to($1,'UTF8'))",[token]);await as(stranger);assert.equal(await rpc('cq_v4_claim_invite',{p_token:token,p_student_name:'Late'}),false);});
test('PDF and approval registration reuse the same owner/book/chapter UUID',async()=>{
 await as(parent);chapter=(await rpc('cq_v4_parent_pdf',{p_action:'create_chapter',p_args:JSON.stringify({book_id:material.p_book_id,chapter_id:material.p_chapter_id,title:'Chapter 1'})})).chapter_uuid;
 approval=await rpc('cq_v4_register_approval_once',material);assert.equal(await rpc('cq_v4_register_approval_once',material),approval);
 await assert.rejects(rpc('cq_v4_register_approval_once',{...material,p_source:'changed'}),/REQUEST_KEY_REUSED/);
 await assert.rejects(rpc('cq_v4_publish_approved',{p_approval_id:approval,p_children:[student]}),/PDF_NOT_READY/);
 await as(parent,'postgres');const row=(await sql('select chapter_uuid from cq_private.approvals where approval_id=$1',[approval]))[0];assert.equal(row.chapter_uuid,chapter);
});
test('PDF readiness cannot be forged by a browser or foreign parent',async()=>{
 await as(other);await assert.rejects(rpc('cq_v4_parent_pdf',{p_action:'upload_url',p_args:JSON.stringify({chapter_uuid:chapter})}),/CHAPTER_NOT_FOUND/);
 await as(parent);const info=await rpc('cq_v4_parent_pdf',{p_action:'upload_url',p_args:JSON.stringify({chapter_uuid:chapter})});assert.equal(info.path,`${parent}/${chapter}/original.pdf`);
 await assert.rejects(rpc('cq_v4_parent_pdf',{p_action:'finalize_upload',p_args:JSON.stringify({chapter_uuid:chapter})}),/VERIFIED_EDGE_REQUIRED/);
 await assert.rejects(rpc('cq_v4_finalize_pdf',{p_chapter_uuid:chapter,p_parent_user_id:parent}),/permission denied/);
 await as(parent,'postgres');await sql('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['cq-v4-originals',info.path,JSON.stringify({size:100,mimetype:'application/pdf'})]);
 await as(parent,'service_role');assert.equal(await rpc('cq_v4_finalize_pdf',{p_chapter_uuid:chapter,p_parent_user_id:parent}),true);
});
test('publishing is idempotent, rejects unlinked children and excludes answer keys',async()=>{
 await as(parent);await assert.rejects(rpc('cq_v4_publish_approved',{p_approval_id:approval,p_children:[stranger]}),/CHILD_NOT_APPROVED/);
 assert.equal(await rpc('cq_v4_publish_approved',{p_approval_id:approval,p_children:[student]}),chapter);assert.equal(await rpc('cq_v4_publish_approved',{p_approval_id:approval,p_children:[student]}),chapter);
 const status=await rpc('cq_v4_publication_status',{p_approval_id:approval,p_children:[student]});assert.equal(status.all_assigned,true);assert.equal(status.content_matches,true);
 await assert.rejects(rpc('cq_v4_parent_pdf',{p_action:'upload_url',p_args:JSON.stringify({chapter_uuid:chapter})}),/PDF_IMMUTABLE/);
 await as(student);const chapters=await sql('select * from public.cq_v4_my_chapters()');assert.equal(chapters.length,1);assert.equal(chapters[0].chapter_uuid,chapter);assert.equal(JSON.stringify(chapters).includes('answer_key'),false);
 await assert.rejects(sql('select * from cq_private.approvals'),/permission denied/);await assert.rejects(sql('select * from public.cq_v4_chapters'),/permission denied/);
 assert.equal(await rpc('cq_v4_pdf_access',{p_chapter_uuid:chapter}),`${parent}/${chapter}/original.pdf`);
 await as(stranger);assert.equal((await sql('select * from public.cq_v4_my_chapters()')).length,0);await assert.rejects(rpc('cq_v4_pdf_access',{p_chapter_uuid:chapter}),/PDF_ACCESS_DENIED/);
});
test('revoke immediately blocks both PDF and questions; reactivation requires parent',async()=>{
 await as(parent);await rpc('cq_v4_revoke_child',{p_child_user_id:student});
 await as(student);assert.equal((await sql('select * from public.cq_v4_my_chapters()')).length,0);await assert.rejects(rpc('cq_v4_pdf_access',{p_chapter_uuid:chapter}),/PDF_ACCESS_DENIED/);
 await as(parent);await rpc('cq_v4_approve_child',{p_child_user_id:student});
});
test('audio storage RLS isolates students and forbids updates; submission verifies audio server-side',async()=>{
 const object=`${student}/${chapter}.webm`;await as(stranger);await assert.rejects(sql('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['cq-v4-speaking',object,JSON.stringify({size:20,mimetype:'audio/webm'})]),/row-level security/);
 await as(student);const answers={readComplete:true,answers:['0'],essay:'My essay',speaking:'My script',hasAudio:true};await assert.rejects(rpc('cq_v4_submit_answers',{p_chapter_uuid:chapter,p_answers:JSON.stringify(answers)}),/AUDIO_REQUIRED/);
 await sql('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['cq-v4-speaking',object,JSON.stringify({size:20,mimetype:'audio/webm'})]);
 assert.equal((await sql("update storage.objects set metadata='{}' where name=$1 returning *",[object])).length,0);
 assert.equal(await rpc('cq_v4_submit_answers',{p_chapter_uuid:chapter,p_answers:JSON.stringify(answers)}),true);
 await assert.rejects(rpc('cq_v4_submit_answers',{p_chapter_uuid:chapter,p_answers:JSON.stringify(answers)}),/ALREADY_SUBMITTED/);
 await assert.rejects(sql('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['cq-v4-speaking',`${student}/${chapter}.mp4`,JSON.stringify({size:20,mimetype:'audio/mp4'})]),/row-level security/);
});
test('feedback is parent-scoped and hidden until released',async()=>{
 await as(other);await assert.rejects(rpc('cq_v4_release_feedback',{p_child_user_id:student,p_chapter_uuid:chapter,p_feedback:'wrong parent',p_release:true}),/SUBMISSION_NOT_FOUND/);
 await as(parent);await rpc('cq_v4_release_feedback',{p_child_user_id:student,p_chapter_uuid:chapter,p_feedback:'Good work',p_release:false});
 await as(student);assert.equal((await sql('select * from public.cq_v4_my_submission($1)',[chapter]))[0].feedback,'');
 await as(parent);await rpc('cq_v4_release_feedback',{p_child_user_id:student,p_chapter_uuid:chapter,p_feedback:'Good work',p_release:true});
 await as(student);assert.equal((await sql('select * from public.cq_v4_my_submission($1)',[chapter]))[0].feedback,'Good work');
});
test('snapshot access requires parent ownership; account invite quota is enforced',async()=>{
 await as(student);await assert.rejects(sql("insert into public.cq_v4_snapshots(owner_id,payload) values($1,'{}')",[student]),/row-level security/);
 await as(parent);await sql("insert into public.cq_v4_snapshots(owner_id,payload) values($1,'{}')",[parent]);await as(other);assert.deepEqual(await sql('select * from public.cq_v4_snapshots'),[]);
 await as(parent);for(let i=0;i<10;i++)await rpc('cq_v4_reserve_account_invite',{p_email:`student${i}@example.test`});await assert.rejects(rpc('cq_v4_reserve_account_invite',{p_email:'one-more@example.test'}),/ACCOUNT_INVITE_RATE_LIMIT/);
});

test('same local IDs belong to different parents; PDF students reuse approved relationship rows',async()=>{
 await as(other);const separate=await rpc('cq_v4_parent_pdf',{p_action:'create_chapter',p_args:JSON.stringify({book_id:material.p_book_id,chapter_id:material.p_chapter_id,title:'Different owner'})});assert.notEqual(separate.chapter_uuid,chapter);
 await as(parent);const students=await rpc('cq_v4_parent_pdf',{p_action:'list_students',p_args:'{}'});assert.deepEqual(students.students.map(x=>x.student_user_id),[student]);
 const assignments=await rpc('cq_v4_parent_pdf',{p_action:'list_assignments',p_args:'{}'});assert.deepEqual(assignments.assignments,[{chapter_uuid:chapter,student_user_id:student}]);
});
test('question answer-key injection and invalid option indices are rejected',async()=>{
 await as(parent);await assert.rejects(rpc('cq_v4_register_approval_once',{...material,p_questions:JSON.stringify([{kind:'mc',text:'Question',options:['A','B'],answer_key:0}])}),/INVALID_QUESTION/);
 const next=(await rpc('cq_v4_parent_pdf',{p_action:'create_chapter',p_args:JSON.stringify({book_id:'next-book',chapter_id:'next-chapter',title:'Next'})})).chapter_uuid;
 const a=await rpc('cq_v4_register_approval_once',{...material,p_request_key:'66666666-6666-4666-8666-666666666666',p_book_id:'next-book',p_chapter_id:'next-chapter'});
 const info=await rpc('cq_v4_parent_pdf',{p_action:'upload_url',p_args:JSON.stringify({chapter_uuid:next})});
 await as(parent,'postgres');await sql('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',['cq-v4-originals',info.path,JSON.stringify({size:100,mimetype:'application/pdf'})]);
 await as(parent,'service_role');await rpc('cq_v4_finalize_pdf',{p_chapter_uuid:next,p_parent_user_id:parent});await as(parent);await rpc('cq_v4_publish_approved',{p_approval_id:a,p_children:[student]});
 await as(student);await assert.rejects(rpc('cq_v4_submit_answers',{p_chapter_uuid:next,p_answers:JSON.stringify({readComplete:true,answers:['99'],essay:'Essay',speaking:'Script'})}),/INVALID_ANSWERS/);
});
test('a fresh claimed invite cannot silently reactivate revoked access',async()=>{
 await as(parent);await rpc('cq_v4_revoke_child',{p_child_user_id:student});const token=await rpc('cq_v4_issue_invite');
 await as(student);assert.equal(await rpc('cq_v4_claim_invite',{p_token:token,p_student_name:'Student again'}),true);assert.equal((await sql('select * from public.cq_v4_my_chapters()')).length,0);
 await as(parent);assert.equal((await sql('select active from public.cq_v4_child_access where child_user_id=$1',[student]))[0].active,false);
});
