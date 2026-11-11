import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url);
let PGlite;try{({PGlite}=require('@electric-sql/pglite'));}catch{({PGlite}=require('../qa-db/node_modules/@electric-sql/pglite'));}
const schema=JSON.parse(await fs.readFile(new URL('./fixtures/live_schema.json',import.meta.url)));
const tables=JSON.parse(await fs.readFile(new URL('./fixtures/table_metadata.json',import.meta.url)));
const ddl=JSON.parse(await fs.readFile(new URL('./fixtures/ddl_details.json',import.meta.url)));
const db=new PGlite();const results=[];
const quote=s=>'"'+s.replaceAll('"','""')+'"';
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE SCHEMA auth;CREATE SCHEMA storage;
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
for(const t of tables.filter(t=>t.rls_enabled))await db.exec('ALTER TABLE '+t.name+' ENABLE ROW LEVEL SECURITY;');
for(const p of schema.policies.filter(p=>p.tablename.startsWith('cq_v4_')||p.tablename==='cq_admins')){
 await db.exec('CREATE POLICY '+quote(p.policyname)+' ON '+p.schemaname+'.'+p.tablename+' AS '+p.permissive+' FOR '+p.cmd+' TO '+p.roles.join(',')+(p.qual?' USING ('+p.qual+')':'')+(p.with_check?' WITH CHECK ('+p.with_check+')':'')+';');
}
await db.exec('GRANT ALL ON public.cq_v4_pdf_chapters,public.cq_v4_pdf_enrollments,public.cq_v4_pdf_assignments,public.cq_v4_snapshots TO authenticated;GRANT SELECT ON public.cq_admins TO authenticated;');
for(const f of schema.functions){const signature='public.'+f.name+'('+f.args+')';await db.exec('REVOKE ALL ON FUNCTION '+signature+' FROM PUBLIC,anon,authenticated;'+(f.authenticated_execute?'GRANT EXECUTE ON FUNCTION '+signature+' TO authenticated;':''));}
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
 await check('live function reproduced: short answer array is incorrectly accepted',()=>asUser(child,async()=>assert.equal((await submit({...full,answers:['0']})).rows.length,1)));
 await check('live grants reproduced: authenticated role has TRUNCATE privilege',async()=>assert.equal((await db.query("select has_table_privilege('authenticated','public.cq_v4_snapshots','TRUNCATE') as allowed")).rows[0].allowed,true));
 await db.exec(await fs.readFile(new URL('./candidate/submit_validation_and_table_privileges.sql',import.meta.url),'utf8'));
 await check('candidate function compiles in isolated PostgreSQL',async()=>assert.ok(true));
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
 await check('original live function can be restored',async()=>{await db.exec(await fs.readFile(new URL('./backup/submit_answers.sql',import.meta.url),'utf8'));});
}finally{
 await fs.writeFile(new URL('./db-isolated-results.json',import.meta.url),JSON.stringify({scope:'PGlite isolated PostgreSQL with synthetic data; live DDL metadata and functions; not hosted Auth/Storage integration',checks:results},null,2));
 console.log(JSON.stringify({passed:results.filter(x=>x.pass).length,total:results.length,checks:results},null,2));await db.close();
}
