import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();
const sql=path=>fs.readFile(new URL(path,import.meta.url),'utf8');
const parent='11111111-1111-4111-8111-111111111111';
const child='22222222-2222-4222-8222-222222222222';
const chapter='44444444-4444-4444-8444-444444444444';
try {
 await db.exec(`create table public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid,primary key(parent_user_id,student_user_id));
 create table public.cq_v4_pdf_chapters(chapter_id uuid primary key);
 insert into public.cq_v4_pdf_enrollments values('${parent}','${child}');
 insert into public.cq_v4_pdf_chapters values('${chapter}');`);
 await db.exec(await sql('./auto-release-policy.REVIEW.sql'));
 await db.exec(await sql('./auto-release-cancellations.REVIEW.sql'));
 await db.exec(`create schema auth;create role anon;create role authenticated;create table public.cq_admins(user_id uuid primary key);insert into public.cq_admins values('${parent}');create function auth.uid() returns uuid language sql stable as $fn$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$fn$;create function public.cq_is_admin() returns boolean language sql stable as $fn$select exists(select 1 from public.cq_admins where user_id=auth.uid())$fn$;`);
 await db.exec(await sql('./auto-release-policy-rpc.REVIEW.sql'));
 await db.exec(await sql('./auto-release-arms.REVIEW.sql'));
 await db.exec(`create table public.cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,released_at timestamptz,primary key(student_user_id,chapter_id));insert into public.cq_v4_lesson_schedule values('${parent}','${child}','${chapter}','2026-11-25',now());`);
 await db.exec(await sql('./auto-release-cancel-rpc.REVIEW.sql'));
 const setPolicy=async(user,enabled,days)=>{await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);return db.query('select public.cq_v4_parent_set_auto_release_policy($1,$2,$3::smallint[])',[child,enabled,days]);};
 await test('policy defaults to disabled and persists selected weekdays',async()=>{
  await db.query('insert into public.cq_v4_auto_release_policies(parent_user_id,student_user_id,weekdays) values($1,$2,$3::smallint[])',[parent,child,[1,3,4]]);
  const row=(await db.query('select enabled,weekdays from public.cq_v4_auto_release_policies')).rows[0];
  assert.equal(row.enabled,false);assert.deepEqual(row.weekdays,[1,3,4]);
 });
 await test('invalid weekday is rejected',async()=>{
  await assert.rejects(db.query('update public.cq_v4_auto_release_policies set weekdays=$1::smallint[]',[[-1,8]]),e=>e.code==='23514');
 });
 await test('unenrolled student policy is rejected',async()=>{
  await assert.rejects(db.query('insert into public.cq_v4_auto_release_policies(parent_user_id,student_user_id) values($1,$2)',[parent,'33333333-3333-4333-8333-333333333333']),e=>e.code==='23503');
 });
 await test('cancellation persists independently of policy toggles',async()=>{
  await db.query('insert into public.cq_v4_auto_release_cancellations(parent_user_id,student_user_id,chapter_id) values($1,$2,$3)',[parent,child,chapter]);
  await db.query('update public.cq_v4_auto_release_policies set enabled=true');
  await db.query('update public.cq_v4_auto_release_policies set enabled=false');
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_cancellations')).rows[0].n,1);
 });
 await test('parent RPC enables valid weekly policy',async()=>{
  await setPolicy(parent,true,[1,3,4]);
  const row=(await db.query('select enabled,weekdays from public.cq_v4_auto_release_policies')).rows[0];
  assert.equal(row.enabled,true);assert.deepEqual(row.weekdays,[1,3,4]);
 });
 await test('student cannot change parent policy',async()=>{
  await assert.rejects(setPolicy(child,false,[2,3,5]),e=>e.code==='42501');
 });
 await test('duplicate weekdays are rejected',async()=>{
  await assert.rejects(setPolicy(parent,true,[1,1,3]),e=>e.code==='22023');
 });
 await test('null enabled flag is rejected',async()=>{
  await assert.rejects(setPolicy(parent,null,[1,3,4]),e=>e.code==='22023');
 });
 await test('parent RPC can disable without deleting cancellation',async()=>{
  await setPolicy(parent,false,[1,3,4]);
  assert.equal((await db.query('select enabled from public.cq_v4_auto_release_policies')).rows[0].enabled,false);
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_cancellations')).rows[0].n,1);
 });
 await test('parent cancellation preserves an existing manual release',async()=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[parent]);
  await db.query('select public.cq_v4_parent_cancel_auto_release($1,$2)',[child,chapter]);
  const row=(await db.query('select released_at from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter])).rows[0];
  assert.ok(row.released_at);
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_cancellations')).rows[0].n,1);
 });
 await test('automatic release cancellation revokes only an explicitly armed chapter',async()=>{
  await db.query('delete from public.cq_v4_auto_release_cancellations where student_user_id=$1 and chapter_id=$2',[child,chapter]);
  await db.query('insert into public.cq_v4_auto_release_arms(parent_user_id,student_user_id,chapter_id) values($1,$2,$3)',[parent,child,chapter]);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[parent]);
  await db.query('select public.cq_v4_parent_cancel_auto_release($1,$2)',[child,chapter]);
  const row=(await db.query('select released_at from public.cq_v4_lesson_schedule where chapter_id=$1',[chapter])).rows[0];
  assert.equal(row.released_at,null);
  const arm=(await db.query('select revoked_at from public.cq_v4_auto_release_arms where chapter_id=$1',[chapter])).rows[0];
  assert.ok(arm.revoked_at);
 });
 await test('student cannot cancel parent automatic release',async()=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[child]);
  await assert.rejects(db.query('select public.cq_v4_parent_cancel_auto_release($1,$2)',[child,chapter]),e=>e.code==='42501');
 });
 await test('repeat parent cancellation is idempotent',async()=>{
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[parent]);
  await db.query('select public.cq_v4_parent_cancel_auto_release($1,$2)',[child,chapter]);
  assert.equal((await db.query('select count(*)::int as n from public.cq_v4_auto_release_cancellations')).rows[0].n,1);
 });
 await test('duplicate cancellation cannot be silently overwritten',async()=>{
  await assert.rejects(db.query('insert into public.cq_v4_auto_release_cancellations(parent_user_id,student_user_id,chapter_id) values($1,$2,$3)',[parent,child,chapter]),e=>e.code==='23505');
 });
} finally {await db.close();}
