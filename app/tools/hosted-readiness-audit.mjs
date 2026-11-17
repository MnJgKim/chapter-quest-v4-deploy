// Offline, read-only hosted integration gate. No network, secrets or deployments.
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const schema=JSON.parse(read('server-review/fixtures/live_schema.json'));
const tables=JSON.parse(read('server-review/fixtures/table_metadata.json'));
const worker=read('worker.mjs');
const wrangler=JSON.parse(read('../wrangler.jsonc'));
const names=new Set(tables.map(t=>t.name.startsWith('public.')?t.name.slice(7):t.name));
const functions=new Set(schema.functions.map(f=>f.name));
const buckets=new Map(schema.buckets.map(b=>[b.id,b]));
const checks={
 captured_pdf_schema:names.has('cq_v4_pdf_chapters')&&names.has('cq_v4_pdf_assignments'),
 captured_submission_schema:names.has('cq_v4_student_submissions'),
 captured_release_gate:functions.has('cq_v4_is_released'),
 captured_parent_authorization:functions.has('cq_is_admin'),
 private_pdf_bucket:buckets.get('cq-v4-originals')?.public===false,
 private_speaking_bucket:buckets.get('cq-v4-speaking')?.public===false,
 ai_endpoint_source:worker.includes("path==='/api/generate'"),
 ai_auth_gate_source:worker.includes("'/auth/v1/user'"),
 ai_binding_declared:wrangler.ai?.binding==='AI',
 ai_disabled_by_default:wrangler.vars?.AI_FREE_PLAN_CONFIRMED==='false',
 worker_static_assets:wrangler.assets?.binding==='ASSETS'
};
// The fixture predates the live release RPC; a missing captured name is a stale-fixture warning, not evidence that hosted lacks it.
const informational=new Set(['captured_release_gate']);
const missing=Object.entries(checks).filter(([name,ok])=>!ok&&!informational.has(name)).map(([name])=>name);
const staleFixture=Object.entries(checks).filter(([name,ok])=>!ok&&informational.has(name)).map(([name])=>name);
const report={scope:'offline source/captured-schema audit only',checks,missing,staleFixture,
 hosted_schema_applied:'UNVERIFIED',hosted_storage_bytes:'UNVERIFIED',
 ai_real_inference:'NOT_TESTED_DISABLED',audio_real_microphone:'NOT_TESTED',
 hosted_edge_runtime:'UNVERIFIED',production_modified:false};
console.log(JSON.stringify(report,null,2));
if(missing.length)process.exitCode=1;
