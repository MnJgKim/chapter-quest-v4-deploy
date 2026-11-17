import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const student='22222222-2222-4222-8222-222222222222';
const parent='11111111-1111-4111-8111-111111111111';
const uuid=n=>'44444444-4444-4444-8444-'+String(n).padStart(12,'0');
const dates=['2026-11-23','2026-11-26','2026-11-30','2026-12-03','2026-12-07','2026-12-10','2026-12-14','2026-12-17','2026-12-21','2026-12-24'];
const expected=['2026-11-23','2026-11-25','2026-11-26','2026-11-30','2026-12-02','2026-12-03','2026-12-07','2026-12-09','2026-12-10','2026-12-14'];
const source=await fs.readFile(new URL('./seowoo-weekday-remap-transaction.REVIEW.sql',import.meta.url),'utf8');
const setup=async()=>{
 const db=new PGlite();
 await db.exec(`create table cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,released_at timestamptz,primary key(student_user_id,chapter_id));
 create unique index cq_student_date_unique on cq_v4_lesson_schedule(student_user_id,lesson_date);
 create table cq_v4_student_submissions(child_user_id uuid,chapter_uuid uuid);
 create table cq_students(id uuid primary key,name text);
 create table cq_student_devices(student_id uuid,auth_user_id uuid,revoked_at timestamptz);
 insert into cq_students values ('33333333-3333-4333-8333-333333333333','이서우');
 insert into cq_student_devices values ('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222',null);
 `);
 for(let i=0;i<10;i++)await db.query('insert into cq_v4_lesson_schedule values ($1,$2,$3,$4,now())',[parent,student,uuid(i+1),dates[i]]);
 return db;
};
const migration=()=>source.replace('v_student uuid := null;','v_student uuid := \''+student+'\';').replace(/\nrollback;\s*$/,'\ncommit;\n');
test('ten existing lessons remap atomically without unique-date collisions',async()=>{
 const db=await setup();
 try{
  await db.exec(migration());
  const rows=(await db.query('select lesson_date::text d,released_at is not null armed from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),expected);
  assert.ok(rows.every(x=>x.armed));
 }finally{await db.close();}
});
test('submission guard rejects remap without changing existing dates',async()=>{
 const db=await setup();
 try{
  await db.query('insert into cq_v4_student_submissions values ($1,$2)',[student,uuid(2)]);
  await assert.rejects(db.exec(migration()),/existing student submission/);
  // A raised exception aborts the transaction; reset it before readback.
  await db.exec('rollback;');
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),dates);
 }finally{await db.close();}
});

test('duplicate original lesson date is rejected before any mutation',async()=>{
 const db=await setup();
 try{
  await db.exec('drop index cq_student_date_unique');
  await db.query('update cq_v4_lesson_schedule set lesson_date=$1 where student_user_id=$2 and chapter_id=$3',[dates[0],student,uuid(2)]);
  await assert.rejects(db.exec(migration()),/duplicate original lesson dates/);
  await db.exec('rollback;');
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),[dates[0],dates[0],...dates.slice(2)]);
 }finally{await db.close();}
});

test('extra scheduled chapter blocks the remap',async()=>{
 const db=await setup();
 try{
  await db.query('insert into cq_v4_lesson_schedule values ($1,$2,$3,$4,now())',[parent,student,uuid(11),'2026-11-25']);
  await assert.rejects(db.exec(migration()),/expected 10 future lessons/);
  await db.exec('rollback;');
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),[...dates,'2026-11-25']);
 }finally{await db.close();}
});
test('unverified student identity cannot change schedules',async()=>{
 const db=await setup();
 try{
  await assert.rejects(db.exec(source.replace(/\nrollback;\s*$/,'\ncommit;\n')),/verified student identity required/);
  await db.exec('rollback;');
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),dates);
 }finally{await db.close();}
});

test('revoked student device blocks remap without changing dates',async()=>{
 const db=await setup();
 try{
  await db.query('update cq_student_devices set revoked_at=now() where auth_user_id=$1',[student]);
  await assert.rejects(db.exec(migration()),/not verified as actively paired/);
  await db.exec('rollback;');
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),dates);
 }finally{await db.close();}
});
