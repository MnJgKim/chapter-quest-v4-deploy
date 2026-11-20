'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const sql=fs.readFileSync('app/sql/development-publish-approved-reread-guard.REVIEW-ONLY.sql','utf8');
const baseline=fs.readFileSync('app/server-review/fixtures/current-functions.sql','utf8');
assert.match(sql,/DEVELOPMENT REVIEW CANDIDATE ONLY/);
assert.match(sql,/CREATE OR REPLACE FUNCTION public\.cq_v4_publish_approved\(p_approval_id uuid, p_children uuid\[\]\)/);
assert.match(sql,/PERFORM public\.cq_v4_assert_reread_publishable\(p_approval_id\)/);
for(const field of ['questions','vocabulary','writing_prompt','speaking_prompt']){
 assert.match(sql,new RegExp('v_current\\.'+field+' IS DISTINCT FROM v_r\\.'+field));
}
assert.match(sql,/FOR UPDATE/);
assert.match(sql,/INSERT INTO public\.cq_v4_pdf_assignments/);
assert.match(baseline,/CREATE OR REPLACE FUNCTION public\.cq_v4_register_approval_once/);
console.log('REREAD_PUBLISH_RPC_CONTRACT_ASSERTIONS_PASSED');
