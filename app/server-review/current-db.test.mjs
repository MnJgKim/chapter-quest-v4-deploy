import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import assert from 'node:assert/strict';
const schema=JSON.parse(await fs.readFile(new URL('./fixtures/live_schema.json',import.meta.url)));
const tables=JSON.parse(await fs.readFile(new URL('./fixtures/table_metadata.json',import.meta.url)));
const ddl=JSON.parse(await fs.readFile(new URL('./fixtures/ddl_details.json',import.meta.url)));
const db=new PGlite();const results=[];
const quote=s=>'"'+s.replaceAll('"','""')+'"';
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;CREATE SCHEMA auth;CREATE SCHEMA storage;
 CREATE TABLE auth.users(id uuid PRIMARY KEY);CREATE TABLE storage.buckets(id text PRIMARY KEY, public boolean DEFAULT false);
 CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text,name text,metadata jsonb DEFAULT '{}'::jsonb);
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 GRANT USAGE ON SCHEMA auth,storage,public TO anon,authenticated;
 GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;`);
for(const t of tables){
 const columns=t.columns.map(c=>{
  const type=c.data_type==='ARRAY'?c.format.slice(1)+'[]':c.data_type==='USER-DEFINED'?c.format:c.data_type;
  return quote(c.name)+' '+type+(c.default_value?' DEFAULT '+c.default_value:'')+(!c.options.includes('nullable')?' NOT NULL':'');
 });
 await db.exec('CREATE TABLE '+t.name+'('+columns.join(',')+');');
}
const constraints=ddl.constraints.filter(c=>tables.some(t=>t.name==='public.'+c.table_name||t.name===c.table_name));
constraints.sort((a,b)=>Number(a.definition.startsWith('FOREIGN KEY'))-Number(b.definition.startsWith('FOREIGN KEY')));
for(const c of constraints)await db.exec('ALTER TABLE public.'+quote(c.table_name.replace(/^public\./,''))+' ADD CONSTRAINT '+quote(c.name)+' '+c.definition+';');
for(const i of ddl.indexes)await db.exec(i);
for(const f of schema.functions)await db.exec(f.definition);
await db.exec(await fs.readFile(new URL('./fixtures/current-functions.sql',import.meta.url),'utf8'));
for(const t of tables.filter(t=>t.rls_enabled))await db.exec('ALTER TABLE '+t.name+' ENABLE ROW LEVEL SECURITY;');
for(const p of schema.policies.filter(p=>p.tablename.startsWith('cq_v4_')||p.tablename==='cq_admins')){
 await db.exec('CREATE POLICY '+quote(p.policyname)+' ON '+p.schemaname+'.'+p.tablename+' AS '+p.permissive+' FOR '+p.cmd+' TO '+p.roles.join(',')+(p.qual?' USING ('+p.qual+')':'')+(p.with_check?' WITH CHECK ('+p.with_check+')':'')+';');
}
await db.exec('GRANT ALL ON public.cq_v4_pdf_chapters,public.cq_v4_pdf_enrollments,public.cq_v4_pdf_assignments,public.cq_v4_snapshots TO authenticated;GRANT SELECT ON public.cq_admins TO authenticated;');
for(const f of schema.functions){const signature='public.'+f.name+'('+f.args+')';await db.exec('REVOKE ALL ON FUNCTION '+signature+' FROM PUBLIC,anon,authenticated;'+(f.authenticated_execute?'GRANT EXECUTE ON FUNCTION '+signature+' TO authenticated;':''));}
const migrationDir=new URL('../local-supabase/supabase/migrations/',import.meta.url);
const parentContextMigration=(await fs.readdir(migrationDir)).find(name=>name.endsWith('_cq_parent_lesson_context.sql'));
await db.exec(await fs.readFile(new URL(parentContextMigration,migrationDir),'utf8'));
await db.exec(await fs.readFile(new URL('20261111233341_cq_verified_pdf_ranges.sql',migrationDir),'utf8'));
const parent='11111111-1111-4111-8111-111111111111',child='22222222-2222-4222-8222-222222222222',outsider='33333333-3333-4333-8333-333333333333',chapter='44444444-4444-4444-8444-444444444444';
await db.exec(`INSERT INTO auth.users VALUES('${parent}'),('${child}'),('${outsider}');INSERT INTO public.cq_admins(user_id) VALUES('${parent}');
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at) VALUES('${chapter}','${parent}','Synthetic test','${parent}/${chapter}.pdf',true,now());
 INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES('${parent}','${child}');
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES('${chapter}','${child}');
 INSERT INTO public.cq_v4_activities(chapter_uuid,questions,published_at) VALUES('${chapter}','[{"kind":"mc","text":"Who?","options":["A","B"]},{"kind":"inference","text":"Why?"}]',now());
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('cq-v4-speaking','${child}/${chapter}.webm','{"size":123,"mimetype":"audio/webm"}');`);
async function asUser(uid,fn){await db.exec('BEGIN;');try{await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[uid]);await db.exec('SET LOCAL ROLE authenticated;');return await fn();}finally{await db.exec('ROLLBACK;');}}
async function check(name,fn){try{await fn();results.push({name,pass:true});}catch(error){results.push({name,pass:false,error:String(error)});throw error;}}
const full={answers:['0','The character helped a friend.'],essay:'The character helped.',speaking:'I can explain.',readComplete:true,hasAudio:true};
const submit=(payload=full)=>db.query('SELECT * FROM public.cq_v4_submit_answers($1,$2::jsonb)',[chapter,JSON.stringify(payload)]);
try{

 const derived='77777777-7777-4777-8777-777777777777',rangeRequest='88888888-8888-4888-8888-888888888888';
 const commitArgs=[parent,rangeRequest,chapter,derived,2,3,4,'Selected chapter','a'.repeat(64),'b'.repeat(64)];
 const commitSql='select public.cq_v4_commit_pdf_range($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id';
 await check('range registry migration grants no direct access to authenticated users',()=>asUser(parent,async()=>assert.rejects(db.query('select * from public.cq_v4_pdf_page_ranges'),e=>e.code==='42501')));
 await check('client cannot execute the privileged range commit',()=>asUser(parent,async()=>assert.rejects(db.query(commitSql,commitArgs),e=>e.code==='42501')));
 await check('server range commit is atomic and idempotent',async()=>{assert.equal((await db.query(commitSql,commitArgs)).rows[0].id,derived);assert.equal((await db.query(commitSql,[...commitArgs.slice(0,3),'99999999-9999-4999-8999-999999999999',...commitArgs.slice(4)])).rows[0].id,derived);assert.equal((await db.query('select count(*)::int as n from public.cq_v4_pdf_page_ranges')).rows[0].n,1);});
 await check('same range request cannot be reused with different pages',async()=>assert.rejects(db.query(commitSql,[...commitArgs.slice(0,4),1,3,...commitArgs.slice(6)]),e=>e.code==='23505'));
 const registerSql='select public.cq_v4_register_range_approval_once($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) as id';
 const args=['99999999-9999-4999-8999-999999999999','book','range-chapter','Selected chapter','Selected source','[{"kind":"mc","text":"Who?","options":["A","B"]}]','[0]','[]','Explain.','Summarize.',chapter,derived,2,3];
 await check('range approval atomically binds derived PDF and cannot rebind whole original',()=>asUser(parent,async()=>{const id=(await db.query(registerSql,args)).rows[0].id;await assert.rejects(db.query('select public.cq_v4_bind_verified_pdf($1,$2)',[id,chapter]),e=>e.code==='23505');}));
 await check('range approval refuses whole original substituted for derived PDF',()=>asUser(parent,async()=>assert.rejects(db.query(registerSql,[...args.slice(0,11),chapter,2,3]),e=>e.code==='42501')));
 await check('range approval refuses forged page bounds',()=>asUser(parent,async()=>assert.rejects(db.query(registerSql,[...args.slice(0,12),1,3]),e=>e.code==='42501')));
 await check('student cannot register verified range approval',()=>asUser(child,async()=>assert.rejects(db.query(registerSql,args),e=>e.code==='42501')));

 await check('parent can read only the owned published lesson context',()=>asUser(parent,async()=>{const rows=(await db.query('select * from public.cq_v4_parent_lesson($1)',[chapter])).rows;assert.equal(rows.length,1);assert.equal(rows[0].questions.length,2);}));
 await check('student cannot execute privileged parent lesson read',()=>asUser(child,async()=>assert.rejects(db.query('select * from public.cq_v4_parent_lesson($1)',[chapter]),e=>e.code==='42501')));
 await check('different registered parent receives no lesson context',()=>asUser(outsider,async()=>{await db.exec('RESET ROLE;');await db.query('insert into public.cq_admins(user_id) values($1)',[outsider]);await db.exec('SET LOCAL ROLE authenticated;');assert.equal((await db.query('select * from public.cq_v4_parent_lesson($1)',[chapter])).rows.length,0);}));
 await check('assigned student sees published questions without answer key',()=>asUser(child,async()=>{const r=await db.query('select * from public.cq_v4_my_chapters()');assert.equal(r.rows.length,1);assert.equal(r.rows[0].chapter_uuid,chapter);assert.ok(!JSON.stringify(r.rows).includes('answer_key'));}));
 await check('unassigned student sees no chapters',()=>asUser(outsider,async()=>assert.equal((await db.query('select * from public.cq_v4_my_chapters()')).rows.length,0)));
 await check('unassigned student sees no activities',()=>asUser(outsider,async()=>assert.equal((await db.query('select * from public.cq_v4_my_chapter_activities($1)',[chapter])).rows.length,0)));
 await check('student cannot read approval answer keys directly',()=>asUser(child,async()=>assert.rejects(db.query('select * from public.cq_v4_approval_requests'),e=>e.code==='42501')));
 await check('student cannot issue parent invitation',()=>asUser(child,async()=>assert.rejects(db.query('select public.cq_v4_issue_invite()'),e=>e.code==='42501')));
 await check('student cannot bind an approval to a PDF',()=>asUser(child,async()=>assert.rejects(db.query('select public.cq_v4_bind_verified_pdf($1,$2)',[chapter,chapter]),e=>e.code==='42501')));

 await db.exec('REVOKE TRUNCATE,TRIGGER,REFERENCES ON public.cq_v4_pdf_chapters,public.cq_v4_pdf_enrollments,public.cq_v4_pdf_assignments,public.cq_v4_snapshots FROM anon,authenticated;');

 await check('parent registration, PDF binding and publication match the client contract',()=>asUser(parent,async()=>{
  const registered=await db.query('select public.cq_v4_register_approval_once($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) as id',['55555555-5555-4555-8555-555555555555','book','chapter','Synthetic lesson','Synthetic source',JSON.stringify([{kind:'mc',text:'Who?',options:['A','B']}]),'[0]','[]','Explain.','Summarize.']);
  const id=registered.rows[0].id;
  const pdfId='66666666-6666-4666-8666-666666666666';
  await db.exec('RESET ROLE;');await db.query('insert into public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at) values($1,$2,$3,$4,true,now())',[pdfId,parent,'Synthetic second PDF',parent+'/'+pdfId+'.pdf']);await db.exec('SET LOCAL ROLE authenticated;');
  assert.equal((await db.query('select public.cq_v4_bind_verified_pdf($1,$2) as id',[id,pdfId])).rows[0].id,pdfId);
  assert.equal((await db.query('select public.cq_v4_publish_approved($1,$2::uuid[]) as id',[id,[child]])).rows[0].id,pdfId);
  const status=(await db.query('select public.cq_v4_publication_status($1,$2::uuid[]) as status',[id,[child]])).rows[0].status;assert.equal(status.content_matches,true);assert.equal(status.all_assigned,true);
  await db.query("select set_config('request.jwt.claim.sub',$1,true)",[child]);
  const rows=(await db.query('select * from public.cq_v4_my_chapters()')).rows;assert.ok(rows.some(x=>x.chapter_uuid===pdfId));assert.ok(!JSON.stringify(rows).includes('correct'));assert.ok(!JSON.stringify(rows).includes('answer_key'));
 }));
 await check('unverified PDF cannot bind to an approval',()=>asUser(parent,async()=>assert.rejects(db.query('select public.cq_v4_bind_verified_pdf($1,$2)',['55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666']),e=>e.code==='42501')));
 await check('feedback stays hidden until parent release, then is visible',()=>asUser(child,async()=>{
  await submit();await db.exec('RESET ROLE;');await db.query('update public.cq_v4_student_submissions set feedback=$1,feedback_released=false where chapter_uuid=$2',['Private draft feedback',chapter]);await db.exec('SET LOCAL ROLE authenticated;');
  assert.equal((await db.query('select * from public.cq_v4_my_submission($1)',[chapter])).rows[0].feedback,null);
  await db.query("select set_config('request.jwt.claim.sub',$1,true)",[parent]);
  assert.equal((await db.query('select * from public.cq_v4_parent_submissions()')).rows.length,1);
  await db.query('select public.cq_v4_release_feedback($1,$2,$3,$4)',[child,chapter,'Great work!',true]);
  await db.query("select set_config('request.jwt.claim.sub',$1,true)",[child]);
  assert.equal((await db.query('select * from public.cq_v4_my_submission($1)',[chapter])).rows[0].feedback,'Great work!');
 }));
 await check('current live function compiles in isolated PostgreSQL',async()=>assert.ok(true));
 await check('short answer array rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0']}),e=>e.code==='22023')));
 await check('extra answer rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0','Text','extra']}),e=>e.code==='22023')));
 await check('empty written answer rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0',' ']}),e=>e.code==='22023')));
 await check('null answer rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0',null]}),e=>e.code==='22023')));
 await check('MC option out of range rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['9','Text']}),e=>e.code==='22023')));
 await check('MC non-integer rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0.2','Text']}),e=>e.code==='22023')));
 await check('non-text written answer rejected',()=>asUser(child,async()=>assert.rejects(submit({...full,answers:['0',42]}),e=>e.code==='22023')));
 await check('unassigned student rejected',()=>asUser(outsider,async()=>assert.rejects(submit(),e=>e.code==='42501')));
 await check('authorized complete submission accepted',()=>asUser(child,async()=>assert.equal((await submit()).rows.length,1)));
 await check('duplicate submit preserves original answers',()=>asUser(child,async()=>{await submit();await submit({...full,essay:'Changed essay'});await db.exec('RESET ROLE;');const row=(await db.query('SELECT answers FROM public.cq_v4_student_submissions WHERE child_user_id=$1',[child])).rows[0];assert.equal(row.answers.essay,full.essay);}));
 await check('TRUNCATE privilege removed without changing snapshot CRUD',async()=>{const r=(await db.query("select has_table_privilege('authenticated','public.cq_v4_snapshots','TRUNCATE') as truncate,has_table_privilege('authenticated','public.cq_v4_snapshots','SELECT,INSERT,UPDATE') as crud")).rows[0];assert.equal(r.truncate,false);assert.equal(r.crud,true);});
}finally{
 await fs.writeFile(new URL('./current-db-results.json',import.meta.url),JSON.stringify({scope:'PGlite isolated PostgreSQL with synthetic data; live DDL metadata and functions; not hosted Auth/Storage integration',checks:results},null,2));
 console.log(JSON.stringify({passed:results.filter(x=>x.pass).length,total:results.length,checks:results},null,2));await db.close();
}
