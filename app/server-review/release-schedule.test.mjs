// Uses actual read-only production function definitions with synthetic rows only.
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$SELECT auth.uid()='11111111-1111-4111-8111-111111111111'::uuid$$;
CREATE TABLE cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid,pdf_ready boolean,title text,created_at timestamptz default now());
CREATE TABLE cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid);
CREATE TABLE cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid);
CREATE TABLE cq_v4_activities(chapter_uuid uuid,published_at timestamptz,questions jsonb,vocabulary jsonb,writing_prompt text,speaking_prompt text);
CREATE TABLE cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,timezone text default 'Asia/Seoul',released_at timestamptz,unique(student_user_id,chapter_id));
CREATE TABLE synthetic_submissions(id int,answers text); INSERT INTO synthetic_submissions VALUES(1,'preserved');`);
await db.exec(readFileSync(new URL('./release-schedule-live.fixture.sql',import.meta.url),'utf8'));
const parent='11111111-1111-4111-8111-111111111111',child='22222222-2222-4222-8222-222222222222',chapter='44444444-4444-4444-8444-444444444444';
await db.query('INSERT INTO cq_v4_pdf_chapters VALUES($1,$2,true,$3,now())',[chapter,parent,'Synthetic']);
await db.query('INSERT INTO cq_v4_pdf_assignments VALUES($1,$2)',[chapter,child]);
await db.query('INSERT INTO cq_v4_pdf_enrollments VALUES($1,$2)',[parent,child]);
await db.query("INSERT INTO cq_v4_activities VALUES($1,now(),'[]','[]','Write','Speak')",[chapter]);
const user=uid=>db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[uid]);
let passed=0;
async function check(name,fn){await fn();passed++;console.log('PASS',name);}
const released=async()=> (await db.query('SELECT cq_v4_is_released($1,$2) AS ok',[chapter,child])).rows[0].ok;
await user(parent);
await db.query("SELECT cq_v4_parent_schedule_lesson($1,$2,((now() at time zone 'Asia/Seoul')::date+7))",[child,chapter]);
await db.query('SELECT cq_v4_parent_set_lesson_release($1,$2,true)',[child,chapter]);
await user(child);
await check('future chapter denied by central gate',async()=>assert.equal(await released(),false));
for(const fn of ['cq_v4_my_released_chapters','cq_v4_my_chapters'])await check(fn+' excludes future chapter',async()=>assert.equal((await db.query('SELECT * FROM '+fn+'()')).rows.length,0));
await check('direct activity lookup excludes future chapter',async()=>assert.equal((await db.query('SELECT * FROM cq_v4_my_chapter_activities($1)',[chapter])).rows.length,0));
await db.exec("UPDATE cq_v4_lesson_schedule SET lesson_date=(now() at time zone 'Asia/Seoul')::date-8");
await check('past released chapter remains available across weeks',async()=>assert.equal(await released(),true));
await check('no new assignments means no next-week duplicates',async()=>assert.equal((await db.query('SELECT * FROM cq_v4_my_released_chapters()')).rows.length,1));
for(const [name,sql] of [ ['unreleased', 'UPDATE cq_v4_lesson_schedule SET released_at=NULL'],['unassigned','DELETE FROM cq_v4_pdf_assignments'],['unpublished','UPDATE cq_v4_activities SET published_at=NULL'],['unverified PDF','UPDATE cq_v4_pdf_chapters SET pdf_ready=false'],['unenrolled','DELETE FROM cq_v4_pdf_enrollments']]){
 await db.exec('BEGIN');await db.exec(sql);await check(name+' chapter denied',async()=>assert.equal(await released(),false));await db.exec('ROLLBACK');
}
// Security regressions: a different enrolled student cannot read another student's released lesson.
const stranger='33333333-3333-4333-8333-333333333333';
await user(stranger);
await check('other student cannot see released chapter',async()=>{
 assert.equal(await released(),false);
 assert.equal((await db.query('SELECT * FROM cq_v4_my_released_chapters()')).rows.length,0);
 assert.equal((await db.query('SELECT * FROM cq_v4_my_chapter_activities($1)',[chapter])).rows.length,0);
});
await check('non-parent cannot schedule or release lesson',async()=>{
 await assert.rejects(db.query('SELECT cq_v4_parent_schedule_lesson($1,$2,current_date)',[child,chapter]),/Parent authorization required/);
 await assert.rejects(db.query('SELECT cq_v4_parent_set_lesson_release($1,$2,true)',[child,chapter]),/Parent authorization required/);
});
await user(parent);
await check('parent cannot schedule an unenrolled student',async()=>{
 await assert.rejects(db.query('SELECT cq_v4_parent_schedule_lesson($1,$2,current_date)',[stranger,chapter]),/Approved PDF and enrolled student required/);
});
await user(child);
await check('submission fixture unchanged',async()=>assert.deepEqual((await db.query('SELECT * FROM synthetic_submissions')).rows,[{id:1,answers:'preserved'}]));
console.log(JSON.stringify({passed,scope:'isolated PGlite; production functions; no hosted writes'}));await db.close();
