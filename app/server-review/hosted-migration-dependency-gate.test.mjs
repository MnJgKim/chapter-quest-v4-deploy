// Offline schema dependency gate: verifies review-only migration prerequisites and safe ordering.
// Never connects to Supabase, executes SQL, or deploys migrations.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=name=>fs.readFileSync(new URL('./'+name,import.meta.url),'utf8');
const files={
 policy:'auto-release-policy.REVIEW.sql',
 cancellations:'auto-release-cancellations.REVIEW.sql',
 arms:'auto-release-arms.REVIEW.sql',
 policyRpc:'auto-release-policy-rpc.REVIEW.sql',
 listRpc:'auto-release-policy-list-rpc.REVIEW.sql',
 cancelRpc:'auto-release-cancel-rpc.REVIEW.sql',
 baseWeek:'weekly-atomic-rpc.REVIEW.sql',
 autoWeek:'auto-release-week-rpc.REVIEW.sql',
 manualOverride:'auto-release-manual-override-rpc.REVIEW.sql'
};
const src=Object.fromEntries(Object.entries(files).map(([key,file])=>[key,read(file)]));
test('all hosted migrations are explicitly review-only',()=>{
 for(const [name,sql] of Object.entries(src))assert.match(sql.slice(0,300),/REVIEW ONLY|DO NOT APPLY TO PRODUCTION/i,name);
});
test('auto release requires opted-in policy and invokes the approval-gated atomic scheduler',()=>{
 assert.match(src.autoWeek,/cq_v4_auto_release_policies/);
 assert.match(src.autoWeek,/p\.enabled\s*=\s*true/);
 assert.match(src.autoWeek,/cq_v4_auto_release_cancellations/);
 assert.match(src.autoWeek,/cq_v4_parent_schedule_week_atomic\(/);
 assert.match(src.baseWeek,/cq_v4_approval_requests/);
 assert.match(src.baseWeek,/content_hash\s*=\s*act\.approval_hash/);
});
test('cancellation and manual override preserve submitted lessons and explicit parent authorization',()=>{
 for(const key of ['cancelRpc','manualOverride']){
  assert.match(src[key],/cq_is_admin\(/,key);
  assert.match(src[key],/cq_v4_student_submissions/,key);
  assert.match(src[key],/cq_v4_auto_release_arms/,key);
 }
});
test('policy and cancellation tables are private and protected by RLS',()=>{
 for(const key of ['policy','cancellations','arms']){
  assert.match(src[key],/revoke all on table/i,key);
  assert.match(src[key],/enable row level security/i,key);
 }
});
test('parent-facing RPCs do not grant anonymous execution',()=>{
 for(const key of ['policyRpc','listRpc','cancelRpc','baseWeek','autoWeek','manualOverride']){
  assert.match(src[key],/revoke all on function[\s\S]*from public,anon;/i,key);
  assert.match(src[key],/grant execute on function[\s\S]*to authenticated;/i,key);
 }
});
