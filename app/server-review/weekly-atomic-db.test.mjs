import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const parent='11111111-1111-4111-8111-111111111111';
const child='22222222-2222-4222-8222-222222222222';
const chapter1='44444444-4444-4444-8444-444444444444';
const chapter2='55555555-5555-4555-8555-555555555555';
const approval1='66666666-6666-4666-8666-666666666666';
const approval2='77777777-7777-4777-8777-777777777777';
const hash='a'.repeat(64);
const sql=path=>fs.readFile(new URL(path,import.meta.url),'utf8');
const db=new PGlite();
try {
 await db.exec(`create schema auth;
 create role anon;create role authenticated;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.cq_admins(user_id uuid primary key);
 create function public.cq_is_admin() returns boolean language sql stable as $$select exists(select 1 from public.cq_admins where user_id=auth.uid())$$;
 create table public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid,primary key(parent_user_id,student_user_id));
 create table public.cq_v4_pdf_chapters(chapter_id uuid primary key,parent_user_id uuid,pdf_ready boolean,pdf_verified_at timestamptz);
 create table public.cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid,primary key(chapter_id,student_user_id));
 create table public.cq_v4_activities(chapter_uuid uuid primary key,published_at timestamptz,approval_id uuid,approval_hash text);
 create table public.cq_v4_approval_requests(id uuid primary key,parent_user_id uuid,chapter_uuid uuid,content_hash text);
 create table public.cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,timezone text default 'Asia/Seoul',released_at timestamptz,primary key(student_user_id,chapter_id));
 insert into public.cq_admins values ('${parent}');
 insert into public.cq_v4_pdf_enrollments values ('${parent}','${child}');
 insert into public.cq_v4_pdf_chapters values ('${chapter1}','${parent}',true,now()),('${chapter2}','${parent}',true,now());
 insert into public.cq_v4_pdf_assignments values ('${chapter1}','${child}'),('${chapter2}','${child}');
 insert into public.cq_v4_activities values ('${chapter1}',now(),'${approval1}','${hash}'),('${chapter2}',now(),'${approval2}','${hash}');
 insert into public.cq_v4_approval_requests values ('${approval1}','${parent}','${chapter1}','${hash}'),('${approval2}','${parent}','${chapter2}','${hash}');
 `);
 await db.exec(await sql('./schedule-student-date-unique.REVIEW.sql'));
 await db.exec(await sql('./weekly-atomic-rpc.REVIEW.sql'));
 const run=async(items,user=parent)=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
  return db.query('select public.cq_v4_parent_schedule_week_atomic($1,$2::jsonb) as inserted',[child,JSON.stringify(items)]);
 };
 const item=(id,date)=>({chapter_id:id,lesson_date:date});
 await test('two approved chapters insert atomically with unreleased rows',async()=>{
  const r=await run([item(chapter1,'2026-11-23'),item(chapter2,'2026-11-25')]);
  assert.equal(r.rows[0].inserted,2);
  const rows=(await db.query('select lesson_date,released_at from public.cq_v4_lesson_schedule order by lesson_date')).rows;
  assert.equal(rows.length,2);assert.ok(rows.every(r=>r.released_at===null));
 });
 await test('duplicate chapter does not overwrite manual date',async()=>{
  await assert.rejects(run([item(chapter1,'2026-11-26')]),e=>e.code==='23505');
  assert.equal((await db.query('select lesson_date::text as date from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter1])).rows[0].date,'2026-11-23');
 });
 await test('student/date unique index blocks other chapter on occupied day',async()=>{
  await assert.rejects(db.query('insert into public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date) values ($1,$2,$3,$4)',[parent,child,chapter2,'2026-11-23']),e=>e.code==='23505');
 });
 await test('unauthorized user cannot schedule',async()=>{
  await assert.rejects(run([],child),e=>e.code==='42501');
 });
 await test('malformed batch rejects and preserves existing rows',async()=>{
  await assert.rejects(run([{chapter_id:'bad',lesson_date:'2026-11-26'}]),e=>e.code==='22023');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_lesson_schedule')).rows[0].n,2);
 });
} finally {
 await db.close();
}
