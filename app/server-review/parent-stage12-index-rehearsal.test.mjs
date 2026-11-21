import pg from 'pg';
import assert from 'node:assert/strict';
const {Client}=pg;
const config={host:'127.0.0.1',port:5432,user:'postgres',password:'postgres',database:'postgres'};
const db=new Client(config);
const table='public.cq_stage12_index_rehearsal';
const index='cq_stage12_index_rehearsal_unique';
let passed=0;
const check=(name)=>{passed++;console.log('PASS',name)};
const student='22222222-2222-4222-8222-222222222222';
const c1='44444444-4444-4444-8444-444444444444';
const c2='55555555-5555-4555-8555-555555555555';
const c3='77777777-7777-4777-8777-777777777777';
const date=(d)=>d.toISOString().slice(0,10);
try{
 await db.connect();
 await db.query('DROP TABLE IF EXISTS '+table+' CASCADE');
 await db.query(`CREATE TABLE ${table}(student_user_id uuid NOT NULL,chapter_id uuid NOT NULL,lesson_date date NOT NULL,released_at timestamptz,PRIMARY KEY(student_user_id,chapter_id))`);
 await db.query(`INSERT INTO ${table} VALUES($1,$2,$3,now()),($1,$4,$5,now())`,[student,c1,'2026-11-23',c2,'2026-11-25']);
 const original=(await db.query(`SELECT chapter_id,lesson_date,released_at FROM ${table} ORDER BY chapter_id`)).rows;
 await db.query(`INSERT INTO ${table} VALUES($1,$2,$3,now())`,[student,c3,'2026-11-23']);
 let failed=false;
 try{await db.query(`CREATE UNIQUE INDEX CONCURRENTLY ${index} ON ${table}(student_user_id,lesson_date)`);}catch(e){failed=true;assert.equal(e.code,'23505');}
 assert.equal(failed,true);
 const invalid=(await db.query(`SELECT i.indisvalid,i.indisready FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.relname=$1`,[index])).rows;
 assert.equal(invalid.length,1);assert.equal(invalid[0].indisvalid,false);
 check('concurrent index fails safely on duplicate and exposes invalid index');
 await db.query(`DROP INDEX CONCURRENTLY IF EXISTS public.${index}`);
 await db.query(`DELETE FROM ${table} WHERE chapter_id=$1`,[c3]);
 await db.query(`SET lock_timeout='3s';SET statement_timeout='30s'`);
 await db.query(`CREATE UNIQUE INDEX CONCURRENTLY ${index} ON ${table}(student_user_id,lesson_date)`);
 const valid=(await db.query(`SELECT i.indisvalid,i.indisready FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.relname=$1`,[index])).rows[0];
 assert.equal(valid.indisvalid,true);assert.equal(valid.indisready,true);
 check('concurrent index succeeds after duplicate removal');
 await assert.rejects(db.query(`INSERT INTO ${table} VALUES($1,$2,$3,now())`,[student,c3,'2026-11-23']),e=>e.code==='23505');
 check('valid index rejects future duplicate');
 const after=(await db.query(`SELECT chapter_id,lesson_date,released_at FROM ${table} ORDER BY chapter_id`)).rows;
 assert.equal(after.length,original.length);
 for(let i=0;i<original.length;i++){
  assert.equal(after[i].chapter_id,original[i].chapter_id);
  assert.equal(date(after[i].lesson_date),date(original[i].lesson_date));
  assert.equal(after[i].released_at.toISOString(),original[i].released_at.toISOString());
 }
 check('pre-existing dates and release timestamps preserved exactly');
 await db.query(`DROP INDEX CONCURRENTLY IF EXISTS public.${index}`);
 const gone=(await db.query('SELECT to_regclass($1) AS value',['public.'+index])).rows[0].value;
 assert.equal(gone,null);
 const preserved=(await db.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n;
 assert.equal(preserved,2);
 check('concurrent rollback removes index without deleting lesson rows');
 console.log(JSON.stringify({passed,scope:'ephemeral PostgreSQL 17 only; concurrent index failure, retry and rollback'}));
}finally{
 await db.query(`DROP INDEX CONCURRENTLY IF EXISTS public.${index}`).catch(()=>{});
 await db.query('DROP TABLE IF EXISTS '+table+' CASCADE').catch(()=>{});
 await db.end().catch(()=>{});
}
