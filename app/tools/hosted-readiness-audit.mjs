// Offline, read-only hosted integration gate. No network, secrets or deployments.
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const schema=JSON.parse(read('server-review/fixtures/live_schema.json'));
const tables=JSON.parse(read('server-review/fixtures/table_metadata.json'));
const worker=read('worker.mjs');
const student=read('public/js/student-app.js');
const wrangler=JSON.parse(read('../wrangler.jsonc'));
const coreSql=read('server-review/hosted-core-contract-readonly.REVIEW.sql');
const storageSql=read('server-review/hosted-storage-security-readonly.REVIEW.sql');
const approvalSql=read('server-review/hosted-approval-readiness-readonly.REVIEW.sql');
const stripSql=s=>s.replace(/--[^\n]*/g,'').replace(/\/\*[\s\S]*?\*\//g,'');
const readonlySql=s=>{
 const clean=stripSql(s).trim();
 // A read-only audit must consist of SELECT/WITH statements only; reject procedural and DDL/DML verbs.
 return /^(?:select|with)\b/i.test(clean)&&!(/\b(create|alter|drop|truncate|insert|update|delete|merge|grant|revoke|execute|call|copy|do|vacuum|refresh|lock)\b/i.test(clean))&&!/\bselect\s+[^;]*\binto\b/i.test(clean);
};

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
 worker_static_assets:wrangler.assets?.binding==='ASSETS',
 audio_capture_supported:student.includes('navigator.mediaDevices?.getUserMedia')&&student.includes('MediaRecorder'),
 audio_private_storage_path:student.includes('/storage/v1/object/sign/cq-v4-speaking/'),
 audio_recovery_supported:student.includes('readRecovery(')&&student.includes('downloadUnsavedVoice('),
 audio_mime_types_supported:student.includes("'audio/webm'")&&student.includes("'audio/mp4'")&&student.includes("'audio/ogg'"),
 core_contract_audit_readonly:readonlySql(coreSql),
 storage_security_audit_readonly:readonlySql(storageSql),
 approval_readiness_audit_readonly:readonlySql(approvalSql)
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
