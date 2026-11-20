import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync('review/sql-candidates/cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql','utf8');
test('frozen reread helper scores exclusively from immutable snapshot',()=>{
 assert.match(sql,/FROM public\.cq_v4_immutable_grading_snapshots snap/);
 assert.doesNotMatch(sql,/cq_v4_approval_requests|cq_v4_activities/);
 assert.match(sql,/sub\.submitted_at=snap\.submitted_at/);
 assert.match(sql,/correct\*10<total\*7/);
 assert.match(sql,/IF total=0 THEN RAISE EXCEPTION/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.cq_v4_record_frozen_reread_internal/);
});
