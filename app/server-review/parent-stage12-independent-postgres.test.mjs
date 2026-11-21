import assert from 'node:assert/strict';
import pg from 'pg';
const {Client}=pg;
const config={host:'127.0.0.1',port:5432,user:'postgres',password:'postgres',database:'postgres'};
const a=new Client(config),b=new Client(config);
let passed=0;
const check=(name)=>{passed++;console.log('PASS',name)};
try{
 await Promise.all([a.connect(),b.connect()]);
 await a.query('DROP TABLE IF EXISTS public.cq_stage12_concurrency_test');
 await a.query(`CREATE TABLE public.cq_stage12_concurrency_test(
  student_user_id uuid NOT NULL, chapter_id uuid NOT NULL,
  lesson_date date NOT NULL, released_at timestamptz,
  PRIMARY KEY(student_user_id,chapter_id),
  UNIQUE(student_user_id,lesson_date))`);
 const student='22222222-2222-4222-8222-222222222222';
 const c1='44444444-4444-4444-8444-444444444444';
 const c2='55555555-5555-4555-8555-555555555555';
 await a.query('INSERT INTO public.cq_stage12_concurrency_test VALUES($1,$2,$3,now()),($1,$4,$5,now())',[student,c1,'2026-11-23',c2,'2026-11-25']);
 await Promise.all([a.query('BEGIN'),b.query('BEGIN')]);
 await a.query('UPDATE public.cq_stage12_concurrency_test SET lesson_date=$1 WHERE student_user_id=$2 AND chapter_id=$3',['2026-11-26',student,c1]);
 const competing=b.query('UPDATE public.cq_stage12_concurrency_test SET lesson_date=$1 WHERE student_user_id=$2 AND chapter_id=$3',['2026-11-26',student,c2]).then(()=>({ok:true}),e=>({ok:false,code:e.code}));
 await a.query('COMMIT');
 const outcome=await competing;
 assert.deepEqual(outcome,{ok:false,code:'23505'});
 await b.query('ROLLBACK');
 check('independent connections: competing date update rejected with 23505');
 const rows=(await a.query('SELECT chapter_id,lesson_date,released_at FROM public.cq_stage12_concurrency_test ORDER BY chapter_id')).rows;
 assert.equal(rows.length,2);
 assert.equal(rows.filter(r=>r.lesson_date.toISOString().slice(0,10)==='2026-11-26').length,1);
 assert.equal(rows.filter(r=>r.lesson_date.toISOString().slice(0,10)==='2026-11-25').length,1);
 assert(rows.every(r=>r.released_at!==null));
 check('independent connections: original second lesson and release stamps preserved');
 console.log(JSON.stringify({passed,scope:'ephemeral PostgreSQL 17 service; two independent pg clients; no production access'}));
}finally{
 await Promise.allSettled([a.query('ROLLBACK'),b.query('ROLLBACK')]);
 await a.query('DROP TABLE IF EXISTS public.cq_stage12_concurrency_test').catch(()=>{});
 await Promise.allSettled([a.end(),b.end()]);
}
