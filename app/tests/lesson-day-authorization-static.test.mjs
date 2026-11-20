// Run: node --test app/tests/lesson-day-authorization-static.test.mjs
// Static preflight only. This does NOT exercise PostgreSQL, Auth, Storage, Edge Functions.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const v2=readFileSync(new URL('../sql/lesson-day-authorization-v2.REVIEW-ONLY.sql',import.meta.url),'utf8');
const v3=readFileSync(new URL('../sql/lesson-day-rpc-storage-v3.REVIEW-ONLY.sql',import.meta.url),'utf8');
test('server clock and authenticated student bind new work',()=>{
 assert.match(v2,/AT TIME ZONE 'Asia\/Seoul'/);
 assert.match(v2,/p_student = \(SELECT auth\.uid\(\)\)/);
 assert.match(v2,/NOT EXISTS \([\s\S]*cq_v4_student_submissions/);
});
test('history stays distinct from start and idempotent submission',()=>{
 assert.doesNotMatch(v2,/CREATE OR REPLACE FUNCTION public\.cq_v4_is_released/);
 assert.match(v3,/Existing immutable submissions are idempotent/);
 assert.match(v3,/RETURN QUERY SELECT existing\.chapter_uuid/);
 assert.match(v3,/cq_v4_can_start_lesson\(p_chapter_uuid,v_uid\)/);
 assert.match(v3,/OR EXISTS \(SELECT 1 FROM public\.cq_v4_student_submissions done/);
});
test('speaking upload restricts writes but does not rewrite reads',()=>{
 assert.match(v3,/AS RESTRICTIVE FOR INSERT/);
 assert.match(v3,/AS RESTRICTIVE FOR UPDATE/);
 assert.doesNotMatch(v3,/FOR SELECT/);
 assert.equal((v3.match(/CASE WHEN split_part\(name,'\/',2\)/g)||[]).length,3);
});
test('scripts are review-only, no student-data deletes',()=>{
 assert.match(v2,/REVIEW ONLY/);
 assert.match(v3,/REVIEW ONLY/);
 assert.doesNotMatch(v2+'\n'+v3,/\bDELETE FROM public\.cq_v4_student_submissions\b/i);
});

test('PDF Edge uses RLS-safe server read predicate',()=>{
 const edge=readFileSync(new URL('../supabase/functions/cq-v4-pdf-link/index.ts',import.meta.url),'utf8');
 assert.match(v2,/CREATE OR REPLACE FUNCTION public\.cq_v4_can_read_lesson/);
 assert.match(edge,/rpc\('cq_v4_can_read_lesson'/);
 assert.doesNotMatch(edge,/\.from\('cq_v4_student_submissions'\)/);
 assert.match(edge,/userClient\.auth\.getUser\(\)/);
});
test('make-up rescheduling is parent approved, auditable and immutable',()=>{
 const makeup=readFileSync(new URL('../sql/makeup-approval-v1.REVIEW-ONLY.sql',import.meta.url),'utf8');
 assert.match(makeup,/public\.cq_is_admin\(\)/);
 assert.match(makeup,/INSERT INTO public\.cq_v4_makeup_approvals/);
 assert.match(makeup,/FOR UPDATE/);
 assert.match(makeup,/Completed lessons cannot be rescheduled/);
 assert.doesNotMatch(makeup,/DELETE FROM public\.cq_v4_student_submissions/i);
});
