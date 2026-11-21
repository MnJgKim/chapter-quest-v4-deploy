import pg from 'pg';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {Client}=pg;
const db=new Client({host:'127.0.0.1',port:5432,user:'postgres',password:'postgres',database:'postgres'});
const parent='11111111-1111-4111-8111-111111111111';
const otherParent='66666666-6666-4666-8666-666666666666';
const outsider='33333333-3333-4333-8333-333333333333';
let passed=0;
async function check(label,fn){await fn();passed++;console.log('PASS',label);}
const uid=async id=>db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[id]);
try{
 await db.connect();
 // Reuse the exact PGlite synthetic fixture; no production connections.
 const fixture=readFileSync(new URL('./parent-stage12-isolated.test.mjs',import.meta.url),'utf8');
 const match=fixture.match(/await db\.exec\(`([\s\S]*?)`\);/);
 assert(match,'isolated synthetic schema fixture missing');
 await db.query(match[1]);
 await db.query("GRANT USAGE ON SCHEMA auth TO authenticated,anon");
 await db.query("GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon");
 await db.query(readFileSync(new URL('./parent-reread-notice-rpcs.REVIEW.sql',import.meta.url),'utf8'));
 await check('definer owner, locked search path and grants',async()=>{
  const rows=(await db.query(`SELECT p.proname,p.prosecdef,p.proowner::regrole::text AS owner,p.proconfig,
    has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('cq_v4_parent_reread_inbox','cq_v4_parent_ack_reread_notice')`)).rows;
  assert.equal(rows.length,2);
  for(const r of rows){assert.equal(r.prosecdef,true);assert.equal(r.owner,'postgres');assert(Array.isArray(r.proconfig) && r.proconfig.some(setting=>/^search_path\s*=/.test(setting)),JSON.stringify(r.proconfig));assert.equal(r.auth_execute,true);assert.equal(r.anon_execute,false);}
 });
 await uid(parent);
 await db.query('SET ROLE authenticated');
 await check('authenticated parent RPC creates one notice, repeated calls are idempotent',async()=>{
  const first=(await db.query('SELECT * FROM public.cq_v4_parent_reread_inbox()')).rows;
  const second=(await db.query('SELECT * FROM public.cq_v4_parent_reread_inbox()')).rows;
  assert.equal(first.length,1);assert.equal(second.length,1);assert.equal(first[0].notice_id,second[0].notice_id);
 });
 await check('authenticated role cannot read or insert notice table directly',async()=>{
  await assert.rejects(db.query('SELECT * FROM public.cq_v4_parent_reread_notices'),e=>e.code==='42501');
  await assert.rejects(db.query("INSERT INTO public.cq_v4_parent_reread_notices(chapter_uuid,student_user_id) VALUES('44444444-4444-4444-8444-444444444444','22222222-2222-4222-8222-222222222222')"),e=>e.code==='42501');
 });
 const notice=(await db.query('SELECT notice_id FROM public.cq_v4_parent_reread_inbox()')).rows[0].notice_id;
 await uid(otherParent);
 await check('different authorized parent cannot read or acknowledge foreign notice',async()=>{
  assert.equal((await db.query('SELECT * FROM public.cq_v4_parent_reread_inbox()')).rows.length,0);
  assert.equal((await db.query('SELECT public.cq_v4_parent_ack_reread_notice($1) AS ok',[notice])).rows[0].ok,false);
 });
 await uid(outsider);
 await check('non-parent authenticated user denied',async()=>{
  await assert.rejects(db.query('SELECT * FROM public.cq_v4_parent_reread_inbox()'),e=>e.code==='42501');
  await assert.rejects(db.query('SELECT public.cq_v4_parent_ack_reread_notice($1)',[notice]),e=>e.code==='42501');
 });
 await db.query('RESET ROLE');
 await db.query('SET ROLE anon');
 await check('anon denied RPC execution and direct table access',async()=>{
  await assert.rejects(db.query('SELECT * FROM public.cq_v4_parent_reread_inbox()'),e=>e.code==='42501');
  await assert.rejects(db.query('SELECT * FROM public.cq_v4_parent_reread_notices'),e=>e.code==='42501');
 });
 await db.query('RESET ROLE');
 await check('synthetic submission and schedule unchanged',async()=>{
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.cq_v4_student_submissions')).rows[0].n,1);
  const r=(await db.query('SELECT lesson_date,released_at FROM public.cq_v4_lesson_schedule')).rows;
  assert.equal(r.length,1);assert.equal(r[0].lesson_date.toISOString().slice(0,10),'2026-11-23');assert(r[0].released_at);
 });
 console.log(JSON.stringify({passed,scope:'ephemeral PostgreSQL 17 with SET ROLE; synthetic fixture; no production writes'}));
}finally{await db.query('RESET ROLE').catch(()=>{});await db.end().catch(()=>{});}
