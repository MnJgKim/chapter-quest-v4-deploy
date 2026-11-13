import pg from 'pg';import {loadTarget,databaseOptions,migrations,isMain,runCli,SafeError} from './common.mjs';import {plan} from './plan.mjs';
export async function apply(env=process.env){
 const target=await loadTarget(env);const client=new pg.Client(databaseOptions(target,env));
 await client.connect();try{
  const present=await client.query("select to_regnamespace('cq_private') as app, to_regnamespace('cq_test_control') as ledger");
  if(present.rows[0].app||present.rows[0].ledger)throw new SafeError('BASELINE_REQUIRES_EMPTY_TEST_PROJECT');
  const schema=await client.query("select to_regclass('auth.users') is not null as auth, to_regclass('storage.objects') is not null as storage");
  if(!schema.rows[0].auth||!schema.rows[0].storage)throw new SafeError('SUPABASE_SYSTEM_SCHEMAS_REQUIRED');
  const existing=(await client.query(`select exists(select 1 from auth.users) or exists(select 1 from storage.objects) or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and not exists(select 1 from pg_depend d where d.objid=c.oid and d.classid='pg_class'::regclass and d.deptype='e')) as user_data`)).rows[0];
  if(existing.user_data)throw new SafeError('FRESH_TEST_PROJECT_CONTAINS_EXISTING_DATA');
  // The reviewed baseline migrations own their transactions. Stop on the first failure, never reset/retry blindly.
  for(const file of await migrations()){try{await client.query(file.source);}catch{throw new SafeError('MIGRATION_FAILED_'+file.name);}console.log('APPLIED '+file.name);}
  await client.query('begin');
  await client.query('create schema cq_test_control');
  await client.query('revoke all on schema cq_test_control from public,anon,authenticated');
  await client.query('create table cq_test_control.target(project_ref text primary key, purpose text not null)');
  await client.query("insert into cq_test_control.target values($1,'disposable-test')",[target.projectRef]);
  await client.query('create table cq_test_control.migrations(name text primary key, sha256 text not null)');
  for(const file of await migrations())await client.query('insert into cq_test_control.migrations values($1,$2)',[file.name,file.sha256]);
  await client.query("notify pgrst, 'reload schema'");await client.query('commit');console.log('PASS migration ledger recorded');
 }finally{await client.end();}
}
export async function assertInstalled(client,target){
 const marker=await client.query('select project_ref,purpose from cq_test_control.target');
 if(marker.rows.length!==1||marker.rows[0].project_ref!==target.projectRef||marker.rows[0].purpose!=='disposable-test')throw new SafeError('TEST_DATABASE_MARKER_MISMATCH');
 const rows=(await client.query('select name,sha256 from cq_test_control.migrations order by name')).rows;const files=await migrations();
 if(rows.length!==files.length||files.some((f,i)=>f.name!==rows[i].name||f.sha256!==rows[i].sha256))throw new SafeError('MIGRATION_HASH_MISMATCH');
}
if(isMain(import.meta.url))await runCli(async()=>{if(!process.argv.includes('--apply'))return plan();if(!process.argv.includes('--fresh-test-only'))throw new SafeError('FRESH_TEST_FLAG_REQUIRED');await apply();});
