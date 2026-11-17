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
  const rows=(await db.query('select lesson_date::text d from cq_v4_lesson_schedule order by chapter_id')).rows;
  assert.deepEqual(rows.map(x=>x.d),dates);
 }finally{await db.close();}
});
