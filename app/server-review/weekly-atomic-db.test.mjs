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
 await test('empty atomic scheduling batch is rejected without mutation',async()=>{
  await assert.rejects(run([]),e=>e.code==='22023');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_lesson_schedule')).rows[0].n,0);
 });
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
 await test('multi-item failure rolls back earlier inserts',async()=>{
  await db.query('delete from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2]);
  await assert.rejects(run([item(chapter2,'2026-11-25'),item(chapter1,'2026-11-26')]),e=>e.code==='23505');
  const rows=(await db.query('select chapter_id from public.cq_v4_lesson_schedule')).rows;
  assert.equal(rows.length,1);assert.equal(rows[0].chapter_id,chapter1);
  await run([item(chapter2,'2026-11-25')]);
 });
 await db.query('delete from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2]);
 await test('unpublished chapter is rejected without changing schedule',async()=>{
  await db.query('update public.cq_v4_activities set published_at=null where chapter_uuid=$1',[chapter2]);
  await assert.rejects(run([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
  await db.query('update public.cq_v4_activities set published_at=now() where chapter_uuid=$1',[chapter2]);
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_lesson_schedule')).rows[0].n,1);
 });
 await test('approval hash mismatch is rejected',async()=>{
  await db.query('update public.cq_v4_activities set approval_hash=$1 where chapter_uuid=$2',['b'.repeat(64),chapter2]);
  await assert.rejects(run([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
  await db.query('update public.cq_v4_activities set approval_hash=$1 where chapter_uuid=$2',[hash,chapter2]);
 });
 await test('unassigned chapter is rejected',async()=>{
  await db.query('delete from public.cq_v4_pdf_assignments where chapter_id=$1',[chapter2]);
  await assert.rejects(run([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
  await db.query('insert into public.cq_v4_pdf_assignments values($1,$2)',[chapter2,child]);
 });
 await test('unverified PDF is rejected',async()=>{
  await db.query('update public.cq_v4_pdf_chapters set pdf_verified_at=null where chapter_id=$1',[chapter2]);
  await assert.rejects(run([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
  await db.query('update public.cq_v4_pdf_chapters set pdf_verified_at=now() where chapter_id=$1',[chapter2]);
 });
 await run([item(chapter2,'2026-11-25')]);
 await test('legacy manual-style insert cannot occupy an existing student date',async()=>{
  const extra='88888888-8888-4888-8888-888888888888';
  await assert.rejects(db.query(
   'insert into public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date) values($1,$2,$3,$4)',
   [parent,child,extra,'2026-11-23']
  ),e=>e.code==='23505');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_lesson_schedule')).rows[0].n,2);
 });
 await test('legacy manual-style date update cannot overwrite another chapter date',async()=>{
  await assert.rejects(db.query(
   'update public.cq_v4_lesson_schedule set lesson_date=$1 where student_user_id=$2 and chapter_id=$3',
   ['2026-11-23',child,chapter2]
  ),e=>e.code==='23505');
  assert.equal((await db.query('select lesson_date::text as date from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2])).rows[0].date,'2026-11-25');
 });
 await db.exec(await sql('./auto-release-policy.REVIEW.sql'));
 await db.exec(await sql('./auto-release-cancellations.REVIEW.sql'));
 await db.exec(await sql('./auto-release-arms.REVIEW.sql'));
 await db.exec(await sql('./auto-release-week-rpc.REVIEW.sql'));
 const auto=async(items,user=parent)=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
  return db.query('select public.cq_v4_parent_schedule_auto_week($1,$2::jsonb) as inserted',[child,JSON.stringify(items)]);
 };
 await test('auto scheduling requires explicit parent opt-in',async()=>{
  await db.query('delete from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2]);
  await assert.rejects(auto([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
 });
 await db.query('insert into public.cq_v4_auto_release_policies(parent_user_id,student_user_id,enabled,weekdays) values($1,$2,true,$3::smallint[])',[parent,child,[1,3,5]]);
 await test('auto scheduling rejects off-day without writing a row',async()=>{
  await assert.rejects(auto([item(chapter2,'2026-11-26')]),e=>e.code==='42501');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_arms')).rows[0].n,0);
 });
 await test('auto scheduling arms only a valid future approved chapter',async()=>{
  const r=await auto([item(chapter2,'2026-11-27')]);
  assert.equal(r.rows[0].inserted,1);
  const row=(await db.query('select released_at from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2])).rows[0];
  assert.ok(row.released_at);
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_arms')).rows[0].n,1);
 });
 await test('cancelled chapter cannot be auto-rearmed after schedule removal',async()=>{
  await db.query('insert into public.cq_v4_auto_release_cancellations(parent_user_id,student_user_id,chapter_id) values($1,$2,$3)',[parent,child,chapter2]);
  await db.query('delete from public.cq_v4_auto_release_arms where chapter_id=$1',[chapter2]);
  await db.query('delete from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2]);
  await assert.rejects(auto([item(chapter2,'2026-11-27')]),e=>e.code==='42501');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_arms')).rows[0].n,0);
  await db.query('delete from public.cq_v4_auto_release_cancellations where chapter_id=$1',[chapter2]);
  await auto([item(chapter2,'2026-11-27')]);
 });
 await db.exec(await sql('./auto-release-policy-rpc.REVIEW.sql'));
 const changePolicy=async(enabled,weekdays)=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[parent]);
  return db.query('select public.cq_v4_parent_set_auto_release_policy($1,$2,$3::smallint[])',[child,enabled,weekdays]);
 };
 await test('disabling auto policy does not silently revoke previously armed lesson',async()=>{
  await changePolicy(false,[1,3,5]);
  const before=(await db.query('select released_at from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2])).rows[0];
  assert.ok(before.released_at);
  const arm=(await db.query('select revoked_at from public.cq_v4_auto_release_arms where chapter_id=$1',[chapter2])).rows[0];
  assert.equal(arm.revoked_at,null);
  assert.equal((await db.query('select enabled from public.cq_v4_auto_release_policies')).rows[0].enabled,false);
 });
 await test('disabled auto policy rejects new auto batches but preserves existing schedule',async()=>{
  await assert.rejects(auto([item(chapter1,'2026-11-30')]),e=>e.code==='42501');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_lesson_schedule')).rows[0].n,2);
 });
 await test('weekday change affects future batches only, not already armed lesson',async()=>{
  await changePolicy(true,[1,3,4]);
  await assert.rejects(auto([item(chapter1,'2026-11-27')]),e=>e.code==='42501');
  const row=(await db.query('select released_at from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter2])).rows[0];
  assert.ok(row.released_at);
  await changePolicy(true,[1,3,5]);
 });
 await test('auto scheduling cannot reassign an already scheduled chapter',async()=>{
  await assert.rejects(auto([item(chapter2,'2026-11-30')]),e=>e.code==='23505');
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
