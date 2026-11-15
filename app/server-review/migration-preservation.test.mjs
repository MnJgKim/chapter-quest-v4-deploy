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

const owner='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',student='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',chapter='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
await db.exec(`INSERT INTO auth.users VALUES('${owner}'),('${student}');INSERT INTO public.cq_admins(user_id) VALUES('${owner}');
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at) VALUES('${chapter}','${owner}','Preserve synthetic original','${owner}/${chapter}.pdf',true,now());
INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES('${owner}','${student}');
INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES('${chapter}','${student}');
INSERT INTO public.cq_v4_activities(chapter_uuid,questions,published_at) VALUES('${chapter}','[{"kind":"mc","text":"Synthetic?","options":["A","B"]}]',now());
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,feedback,feedback_released) VALUES('${chapter}','${student}','{"essay":"Preserve this record"}','Preserve feedback',true);
INSERT INTO storage.buckets(id,public) VALUES('cq-v4-originals',false);
INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('cq-v4-originals','${owner}/${chapter}.pdf','{"size":123}');`);
const names=[...tables.map(t=>t.name),'auth.users','storage.objects','storage.buckets'];
async function snapshot(){const result={};for(const name of names)result[name]=(await db.query('SELECT row_to_json(t) AS row FROM '+name+' t ORDER BY row_to_json(t)::text')).rows;return result;}
const before=await snapshot();
const definitions=await db.query("select oid::regprocedure::text as signature,pg_get_functiondef(oid) as definition from pg_proc where pronamespace='public'::regnamespace order by 1");
const migrationDir=new URL('../local-supabase/supabase/migrations/',import.meta.url);
const migrations=await Promise.all(['20261111013217_cq_parent_lesson_context.sql','20261111233341_cq_verified_pdf_ranges.sql'].map(n=>fs.readFile(new URL(n,migrationDir),'utf8')));
await db.exec('BEGIN;'+migrations.join('\n')+'COMMIT;');
assert.deepEqual(await snapshot(),before);
for(const row of definitions.rows)assert.equal((await db.query('select pg_get_functiondef($1::regprocedure) as definition',[row.signature])).rows[0].definition,row.definition);
await assert.rejects(db.exec('BEGIN;'+migrations.join('\n')+'COMMIT;'));await db.exec('ROLLBACK;');assert.deepEqual(await snapshot(),before);
console.log(JSON.stringify({scope:'isolated synthetic migration preservation; no hosted data',checks:['existing table rows including student submission and feedback identical','Auth users and Storage metadata identical','existing public function definitions identical','reapplication fails instead of overwriting; rollback preserves rows'],passed:4}));await db.close();
