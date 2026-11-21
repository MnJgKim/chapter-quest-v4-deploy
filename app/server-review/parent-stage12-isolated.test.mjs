import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const parent='11111111-1111-4111-8111-111111111111';
const child='22222222-2222-4222-8222-222222222222';
const outsider='33333333-3333-4333-8333-333333333333';
const chapter='44444444-4444-4444-8444-444444444444';
const otherChapter='55555555-5555-4555-8555-555555555555';
let passed=0;
async function check(name,fn){await fn();passed++;console.log('PASS',name);}
const uid=async id=>db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[id]);
try{
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE SCHEMA auth;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid()='11111111-1111-4111-8111-111111111111'::uuid $$;
 CREATE TABLE cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL);
 CREATE TABLE cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid);
 CREATE TABLE cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid);
 CREATE TABLE cq_v4_student_submissions(chapter_uuid uuid,child_user_id uuid,submitted_at timestamptz DEFAULT now(),PRIMARY KEY(chapter_uuid,child_user_id));
 CREATE TABLE cq_v4_reread_progress(chapter_uuid uuid,child_user_id uuid,required boolean NOT NULL,completed_at timestamptz,PRIMARY KEY(chapter_uuid,child_user_id),FOREIGN KEY(chapter_uuid,child_user_id) REFERENCES cq_v4_student_submissions(chapter_uuid,child_user_id));
 CREATE TABLE cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,released_at timestamptz,PRIMARY KEY(student_user_id,chapter_id));
 INSERT INTO cq_v4_pdf_chapters VALUES('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111'),('55555555-5555-4555-8555-555555555555','11111111-1111-4111-8111-111111111111');
 INSERT INTO cq_v4_pdf_assignments VALUES('44444444-4444-4444-8444-444444444444','22222222-2222-4222-8222-222222222222');
 INSERT INTO cq_v4_pdf_enrollments VALUES('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222');
 INSERT INTO cq_v4_student_submissions(chapter_uuid,child_user_id) VALUES('44444444-4444-4444-8444-444444444444','22222222-2222-4222-8222-222222222222');
 INSERT INTO cq_v4_reread_progress VALUES('44444444-4444-4444-8444-444444444444','22222222-2222-4222-8222-222222222222',true,NULL);
 INSERT INTO cq_v4_lesson_schedule VALUES('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','44444444-4444-4444-8444-444444444444','2026-11-23',now());`);
 await db.exec(readFileSync(new URL('./parent-schedule-student-day-unique.REVIEW.sql',import.meta.url),'utf8'));
 await check('preserve original date and release',async()=>{const r=(await db.query('SELECT lesson_date,released_at IS NOT NULL AS released FROM cq_v4_lesson_schedule')).rows[0];assert.equal(String(r.lesson_date).slice(0,10),'2026-11-23');assert.equal(r.released,true);});
 await check('reject different chapter on same student/day',async()=>assert.rejects(db.query('INSERT INTO cq_v4_lesson_schedule VALUES($1,$2,$3,$4)',[parent,child,otherChapter,'2026-11-23']),e=>e.code==='23505'));
 await check('permit another day',async()=>{await db.query('INSERT INTO cq_v4_lesson_schedule VALUES($1,$2,$3,$4)',[parent,child,otherChapter,'2026-11-25']);});
 await check('simultaneous conflicting updates leave no duplicate student/day',async()=>{
  const results=await Promise.allSettled([
   db.query('UPDATE cq_v4_lesson_schedule SET lesson_date=$1 WHERE student_user_id=$2 AND chapter_id=$3',['2026-11-26',child,chapter]),
   db.query('UPDATE cq_v4_lesson_schedule SET lesson_date=$1 WHERE student_user_id=$2 AND chapter_id=$3',['2026-11-26',child,otherChapter])
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.filter(r=>r.status==='rejected').length,1);
  const rows=(await db.query('SELECT count(*)::int AS n FROM cq_v4_lesson_schedule WHERE student_user_id=$1 AND lesson_date=$2',[child,'2026-11-26'])).rows;
  assert.equal(rows[0].n,1);
 });
 await db.exec(readFileSync(new URL('./parent-reread-notice-rpcs.REVIEW.sql',import.meta.url),'utf8'));
 await uid(parent);
 await check('parent inbox idempotent',async()=>{const a=(await db.query('SELECT * FROM cq_v4_parent_reread_inbox()')).rows;const b=(await db.query('SELECT * FROM cq_v4_parent_reread_inbox()')).rows;assert.equal(a.length,1);assert.equal(b.length,1);assert.equal(a[0].notice_id,b[0].notice_id);assert.equal(a[0].correct_mc,null);});
 const notice=(await db.query('SELECT notice_id FROM cq_v4_parent_reread_inbox()')).rows[0].notice_id;
 await check('parent acknowledgement idempotent',async()=>{assert.equal((await db.query('SELECT cq_v4_parent_ack_reread_notice($1) AS ok',[notice])).rows[0].ok,true);assert.equal((await db.query('SELECT cq_v4_parent_ack_reread_notice($1) AS ok',[notice])).rows[0].ok,true);});
 await uid(outsider);
 await check('outsider inbox rejected',async()=>assert.rejects(db.query('SELECT * FROM cq_v4_parent_reread_inbox()'),e=>e.code==='42501'));
 await check('outsider ack rejected',async()=>assert.rejects(db.query('SELECT cq_v4_parent_ack_reread_notice($1)',[notice]),e=>e.code==='42501'));
 await check('original student submission preserved',async()=>assert.equal((await db.query('SELECT count(*)::int AS n FROM cq_v4_student_submissions')).rows[0].n,1));
 console.log(JSON.stringify({passed,scope:'isolated PGlite synthetic schema; no production writes'}));
}finally{await db.close();}
