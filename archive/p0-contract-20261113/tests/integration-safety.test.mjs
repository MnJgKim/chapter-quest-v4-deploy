import {mkdtemp,writeFile,readFile,chmod,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {test} from 'node:test';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';import {validateTarget,databaseOptions,migrations} from '../scripts/integration/common.mjs';import {pdfFixture} from '../scripts/integration/probe.mjs';
const ref='abcdefghijklmnopqrst';const target={kind:'hosted',purpose:'disposable-test',confirmedDisposable:true,projectRef:ref,supabaseUrl:`https://${ref}.supabase.co`,databaseHost:`db.${ref}.supabase.co`,appOrigin:'http://127.0.0.1:8787',workerOrigin:'http://127.0.0.1:8787'};const env={CQ_TEST_CONFIRMED_PROJECT_REF:ref};
test('integration gate rejects missing confirmation, wrong ref and ambiguous targets',()=>{
 assert.throws(()=>validateTarget({...target,confirmedDisposable:false},env),/TEST_PROJECT_NOT_CONFIRMED/);assert.throws(()=>validateTarget(target,{}),/MISSING/);assert.throws(()=>validateTarget({...target,supabaseUrl:'https://production.supabase.co'},env),/PROJECT_REF_URL_MISMATCH/);assert.throws(()=>validateTarget({...target,workerOrigin:'http://external.example'},env),/UNSAFE_WORKER_ORIGIN/);assert.throws(()=>validateTarget({...target,appOrigin:'https://test.example/path'},env),/ORIGIN_REQUIRED/);assert.equal(validateTarget(target,env).projectRef,ref);
});
test('DB target is bound to reviewed project and cannot disable TLS',()=>{
 const valid={CQ_TEST_DATABASE_URL:`postgresql://postgres:dummy-test@db.${ref}.supabase.co/postgres`};assert.equal(databaseOptions(target,valid).ssl.rejectUnauthorized,true);
 assert.throws(()=>databaseOptions(target,{CQ_TEST_DATABASE_URL:'postgresql://postgres:test@other.example/postgres'}),/DATABASE_TARGET_MISMATCH/);assert.throws(()=>databaseOptions(target,{CQ_TEST_DATABASE_URL:valid.CQ_TEST_DATABASE_URL+'?sslmode=disable'}),/TLS_VERIFICATION_REQUIRED/);
 const pooled={...target,databaseHost:'aws-0-region.pooler.supabase.com'};assert.throws(()=>databaseOptions(pooled,{CQ_TEST_DATABASE_URL:'postgresql://postgres:test@aws-0-region.pooler.supabase.com/postgres'}),/DATABASE_PROJECT_ID_UNBOUND/);
 assert.equal(databaseOptions(pooled,{CQ_TEST_DATABASE_URL:`postgresql://postgres.${ref}:test@aws-0-region.pooler.supabase.com/postgres`}).ssl.rejectUnauthorized,true);
});
test('local target cannot point at a remote API or remote DB',()=>{
 const local={...target,kind:'local',projectRef:'cq-local',supabaseUrl:'http://127.0.0.1:54331',databaseHost:'127.0.0.1'};assert.equal(validateTarget(local,{CQ_TEST_CONFIRMED_PROJECT_REF:'cq-local'}).kind,'local');assert.throws(()=>validateTarget({...local,supabaseUrl:'http://remote:54331'},{CQ_TEST_CONFIRMED_PROJECT_REF:'cq-local'}),/LOCAL_TARGET_NOT_LOOPBACK/);
});
test('offline plan and default apply have no remote prerequisites and reveal no secret values',()=>{
 for(const script of ['plan','apply']){const result=spawnSync(process.execPath,[`scripts/integration/${script}.mjs`],{cwd:new URL('../',import.meta.url),env:{...process.env,CQ_TEST_SERVICE_ROLE_KEY:'must-never-appear',CQ_TEST_TARGET_FILE:''},encoding:'utf8'});assert.equal(result.status,0);assert.match(result.stdout,/OFFLINE PLAN/);assert.equal(result.stdout.includes('must-never-appear'),false);}
});
test('unconfirmed apply/probe/model commands fail closed before any external request',()=>{
 for(const [name,flags] of [['apply',['--apply','--fresh-test-only']],['probe',['--run']],['model',['--run','--allow-model-cost']],['worker-vars',['--write']],['deploy-functions',['--deploy']]]){const result=spawnSync(process.execPath,[`scripts/integration/${name}.mjs`,...flags],{cwd:new URL('../',import.meta.url),env:{...process.env,CQ_TEST_TARGET_FILE:'',CQ_TEST_SERVICE_ROLE_KEY:'never-log-me'},encoding:'utf8'});assert.notEqual(result.status,0);assert.match(result.stderr,/MISSING_CQ_TEST_TARGET_FILE/);assert.equal((result.stdout+result.stderr).includes('never-log-me'),false);}
});
test('migration inventory includes all four unchanged reviewed files and fixture is a valid PDF envelope',async()=>{
 const files=await migrations();assert.equal(files.length,4);assert.ok(files.every(f=>/^[a-f0-9]{64}$/.test(f.sha256)));const pdf=pdfFixture().toString();assert.ok(pdf.startsWith('%PDF-1.4'));assert.match(pdf,/xref\n0 6/);assert.ok(pdf.endsWith('%%EOF\n'));
});

test('unexpected driver/upstream errors are redacted at the CLI boundary',()=>{
 const code="import {runCli} from './scripts/integration/common.mjs';await runCli(async()=>{throw new Error('credential-must-never-be-logged')});";
 const result=spawnSync(process.execPath,['--input-type=module','-e',code],{cwd:new URL('../',import.meta.url),encoding:'utf8'});assert.equal(result.status,1);assert.match(result.stderr,/INTEGRATION_FAILED_NO_SECRETS_LOGGED/);assert.equal((result.stderr+result.stdout).includes('credential-must-never-be-logged'),false);
});

test('confirmed test deployment wrapper binds every command to its ref and server-side bundling',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'cq-integration-cli-'));
 try{
  const manifest=join(dir,'target.json'),log=join(dir,'calls.jsonl'),cli=join(dir,'fake-cli');await writeFile(manifest,JSON.stringify(target));
  await writeFile(cli,"#!/usr/bin/env node\nrequire('fs').appendFileSync(process.env.CQ_FAKE_LOG,JSON.stringify(process.argv.slice(2))+'\\n');\n");await chmod(cli,0o700);
  const result=spawnSync(process.execPath,['scripts/integration/deploy-functions.mjs','--deploy'],{cwd:new URL('../',import.meta.url),env:{...process.env,CQ_TEST_TARGET_FILE:manifest,CQ_TEST_CONFIRMED_PROJECT_REF:ref,CQ_TEST_SUPABASE_CLI:cli,SUPABASE_ACCESS_TOKEN:'dummy-never-print-token',CQ_FAKE_LOG:log},encoding:'utf8'});assert.equal(result.status,0);assert.equal((result.stdout+result.stderr).includes('dummy-never-print-token'),false);
  const calls=(await readFile(log,'utf8')).trim().split('\n').map(line=>JSON.parse(line));assert.equal(calls.length,4);for(const call of calls)assert.equal(call[call.indexOf('--project-ref')+1],ref);assert.deepEqual(calls[0].slice(0,2),['secrets','set']);for(const call of calls.slice(1)){assert.ok(call.includes('--use-api'));assert.ok(!call.includes('--no-verify-jwt'));}
 }finally{await rm(dir,{recursive:true,force:true});}
});
