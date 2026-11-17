import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const db=new PGlite();
const sql=await fs.readFile(new URL('./book-identity.REVIEW.sql',import.meta.url),'utf8');
const p1='11111111-1111-4111-8111-111111111111';
const p2='22222222-2222-4222-8222-222222222222';
const c1='33333333-3333-4333-8333-333333333333';
const c2='44444444-4444-4444-8444-444444444444';
const b1='55555555-5555-4555-8555-555555555555';
const b2='66666666-6666-4666-8666-666666666666';
try {
 await db.exec(`create role anon;create role authenticated;
 create schema auth;create table auth.users(id uuid primary key);
 insert into auth.users values('${p1}'),('${p2}');
 create table public.cq_v4_pdf_chapters(chapter_id uuid primary key,parent_user_id uuid not null,title text not null);
 insert into public.cq_v4_pdf_chapters values('${c1}','${p1}','Chapter 1 : The Dark Woods'),('${c2}','${p2}','Chapter 1 : Another Book');
 create table public.cq_v4_lesson_schedule(chapter_id uuid primary key,lesson_date date);
 insert into public.cq_v4_lesson_schedule values('${c1}','2026-11-23');`);
 await db.exec(sql);
 await db.exec(`create table public.cq_admins(user_id uuid primary key);
 insert into public.cq_admins values('${p1}');
 create function auth.uid() returns uuid language sql stable as $fn$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$fn$;
 create function public.cq_is_admin() returns boolean language sql stable as $fn$select exists(select 1 from public.cq_admins where user_id=auth.uid())$fn$;`);
 await db.exec(await fs.readFile(new URL('./book-identity-rpc.REVIEW.sql',import.meta.url),'utf8'));
 const acting=async(uid)=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
 await test('book API denies unauthenticated and non-admin callers',async()=>{
  await acting(p2);
  await assert.rejects(db.query('select * from public.cq_v4_parent_list_books()'),e=>e.code==='42501');
  await assert.rejects(db.query("select public.cq_v4_parent_create_book('Unauthorized')"),e=>e.code==='42501');
  await acting('');
  await assert.rejects(db.query('select * from public.cq_v4_parent_list_books()'),e=>e.code==='42501');
  await acting(p1);
 });
 await test('book API creates and lists owned books',async()=>{
  await acting(p1);
  const result=await db.query("select public.cq_v4_parent_create_book('  Another Book  ') as id");
  const id=result.rows[0].id;
  const books=await db.query('select * from public.cq_v4_parent_list_books() where book_id=$1',[id]);
  assert.equal(books.rows[0].title,'Another Book');
  assert.equal(Number(books.rows[0].chapter_count),0);
 });
 await test('existing chapters and schedules remain unchanged',async()=>{
  const a=await db.query('select count(*)::int as n from public.cq_v4_pdf_chapters');
  const b=await db.query('select lesson_date::text as d from public.cq_v4_lesson_schedule');
  assert.equal(a.rows[0].n,2);assert.equal(b.rows[0].d,'2026-11-23');
 });
 await test('book tables have RLS and no direct authenticated/anon access',async()=>{
  for(const table of ['cq_v4_books','cq_v4_book_chapters']){
   const r=await db.query(`select relrowsecurity from pg_class where oid=$1::regclass`,['public.'+table]);
   assert.equal(r.rows[0].relrowsecurity,true);
   for(const role of ['anon','authenticated']){
    const p=await db.query('select has_table_privilege($1,$2,\'INSERT\') as w,has_table_privilege($1,$2,\'SELECT\') as r',[role,'public.'+table]);
    assert.equal(p.rows[0].w,false);assert.equal(p.rows[0].r,false);
   }
  }
 });
 await db.query('insert into public.cq_v4_books(book_id,parent_user_id,title) values($1,$2,$3),($4,$5,$6)',[b1,p1,'Magic Tree House 2',b2,p2,'Other']);
 await test('valid owner can map existing chapter',async()=>{
  await db.query('insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number) values($1,$2,$3,1)',[c1,b1,p1]);
  const r=await db.query('select chapter_number from public.cq_v4_book_chapters where chapter_id=$1',[c1]);
  assert.equal(r.rows[0].chapter_number,1);
 });
 await test('cross-parent chapter mapping is rejected by foreign keys',async()=>{
  await assert.rejects(db.query('insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number) values($1,$2,$3,2)',[c2,b1,p1]),e=>e.code==='23503');
  await assert.rejects(db.query('insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number) values($1,$2,$3,2)',[c2,b2,p1]),e=>e.code==='23503');
 });
 await test('chapter cannot be mapped twice',async()=>{
  await assert.rejects(db.query('insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number) values($1,$2,$3,2)',[c1,b1,p1]),e=>e.code==='23505');
 });
 await test('duplicate chapter number in one book is rejected',async()=>{
  const c3='77777777-7777-4777-8777-777777777777';
  await db.query('insert into public.cq_v4_pdf_chapters values($1,$2,$3)',[c3,p1,'Chapter 1 : Duplicate']);
  await assert.rejects(db.query('insert into public.cq_v4_book_chapters(chapter_id,book_id,parent_user_id,chapter_number) values($1,$2,$3,1)',[c3,b1,p1]),e=>e.code==='23505');
 });
} finally {await db.close();}
