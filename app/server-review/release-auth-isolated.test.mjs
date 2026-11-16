// Isolated PGlite regression test. Never connects to hosted Supabase.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();
const read=name=>fs.readFile(new URL(name,import.meta.url),'utf8');
const parent='11111111-1111-4111-8111-111111111111';
const child='22222222-2222-4222-8222-222222222222';
const outsider='33333333-3333-4333-8333-333333333333';
const chapter='44444444-4444-4444-8444-444444444444';
const path=child+'/'+chapter+'.webm';
const checks=[];
async function check(name,fn){try{await fn();checks.push({name,pass:true});}catch(e){checks.push({name,pass:false,error:String(e)});}}
async function asUser(uid,fn){
 await db.exec('BEGIN');
 try{
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[uid]);
  await db.exec('SET LOCAL ROLE authenticated');
  return await fn();
 }finally{await db.exec('ROLLBACK');}
}
await db.exec(`
CREATE ROLE anon;CREATE ROLE authenticated;CREATE SCHEMA auth;CREATE SCHEMA storage;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE public.cq_admins(user_id uuid PRIMARY KEY);
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL,pdf_ready boolean NOT NULL);
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid NOT NULL,student_user_id uuid NOT NULL);
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid NOT NULL,student_user_id uuid NOT NULL);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid NOT NULL,published_at timestamptz);
CREATE TABLE storage.objects(bucket_id text NOT NULL,name text NOT NULL);
GRANT USAGE ON SCHEMA public,auth,storage TO authenticated;
GRANT SELECT,INSERT ON storage.objects TO authenticated;
-- Storage RLS joins these public tables as the authenticated caller.
-- Synthetic fixture has no public-table RLS; only release-function/Storage-RLS behavior is in scope.
GRANT SELECT ON public.cq_v4_pdf_chapters,public.cq_v4_pdf_assignments,
 public.cq_v4_pdf_enrollments,public.cq_v4_activities TO authenticated;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO '' AS $$
SELECT EXISTS (SELECT 1 FROM public.cq_admins a WHERE a.user_id=(SELECT auth.uid()))
$$;
`);
await db.exec(await read('./release-auth-baseline.fixture.sql'));
await db.exec(await read('./release-auth-speaking.fixture.sql'));
await db.exec(`INSERT INTO public.cq_admins VALUES ('${parent}'),('${outsider}');
INSERT INTO public.cq_v4_pdf_chapters VALUES ('${chapter}','${parent}',true);
INSERT INTO public.cq_v4_pdf_assignments VALUES ('${chapter}','${child}');
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('${parent}','${child}');
INSERT INTO public.cq_v4_activities VALUES ('${chapter}',now());
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at)
VALUES ('${parent}','${child}','${chapter}',(now() AT TIME ZONE 'Asia/Seoul')::date,now());
INSERT INTO storage.objects VALUES ('cq-v4-speaking','${path}');
`);
// Prove the original release function exposes a release boolean to an unrelated admin.
// This must be true in the isolated baseline and false after applying the candidate.
await check('baseline reproduces unrelated-admin release disclosure',()=>asUser(outsider,async()=>{
 const r=await db.query('SELECT public.cq_v4_is_released($1,$2) AS allowed',[chapter,child]);
 assert.equal(r.rows[0].allowed,true);
}));
await db.exec(await read('./release-auth-candidate.sql'));
const release=(u,student=child)=>asUser(u,async()=>{
 const r=await db.query('SELECT public.cq_v4_is_released($1,$2) AS allowed',[chapter,student]);
 return r.rows[0].allowed;
});
const readAudio=u=>asUser(u,async()=>{
 const r=await db.query('SELECT name FROM storage.objects WHERE bucket_id=$1 AND name=$2',['cq-v4-speaking',path]);
 return r.rows.length;
});
await check('assigned student release true',async()=>assert.equal(await release(child),true));
await check('owning parent release true',async()=>assert.equal(await release(parent),true));
await check('unrelated admin release false',async()=>assert.equal(await release(outsider),false));
await check('student cannot inspect other release',async()=>assert.equal(await release(child,outsider),false));
await check('student can read own recording',async()=>assert.equal(await readAudio(child),1));
await check('parent can read child recording',async()=>assert.equal(await readAudio(parent),1));
await check('unrelated admin cannot read child recording',async()=>assert.equal(await readAudio(outsider),0));
await check('student recording insert allowed',()=>asUser(child,async()=>{
 const r=await db.query('INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2) RETURNING name',['cq-v4-speaking',path]);
 assert.equal(r.rows.length,1);
}));
await check('outsider recording insert denied',()=>asUser(outsider,async()=>{
 await assert.rejects(db.query('INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2)',['cq-v4-speaking',path]),e=>e.code==='42501');
}));
await db.query("UPDATE public.cq_v4_lesson_schedule SET lesson_date=((now() AT TIME ZONE 'Asia/Seoul')::date+1) WHERE chapter_id=$1",[chapter]);
await check('future lesson not released',async()=>assert.equal(await release(child),false));
await check('future lesson recording not readable',async()=>assert.equal(await readAudio(parent),0));
console.log(JSON.stringify({scope:'isolated PGlite; no hosted data',checks,passed:checks.filter(x=>x.pass).length,total:checks.length},null,2));
await db.close();
if(checks.some(x=>!x.pass))process.exitCode=1;
