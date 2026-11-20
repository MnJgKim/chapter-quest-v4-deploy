import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const prod=readFileSync('review/sql-candidates/cq_v4_submit_v3b_minimal_reread.REVIEW-ONLY.sql','utf8');
test('V3B overlay preserves live production release, assignment, answer and audio validation',()=>{
 for(const fragment of ['cq_v4_is_released(p_chapter_uuid,v_uid)','Assignment unavailable','Answer count mismatch',"bucket_id='cq-v4-speaking'",'Speaking recording not uploaded','ON CONFLICT DO NOTHING'])assert.ok(prod.includes(fragment),fragment);
 assert.doesNotMatch(prod,/cq_v4_can_start_approved_lesson/);
 assert.doesNotMatch(prod,/ALTER POLICY/);
});
test('V3B overlay scores only newly inserted verified approvals and never rescales legacy history',()=>{
 assert.match(prod,/req\.parent_user_id=c\.parent_user_id/);
 assert.match(prod,/req\.content_hash=act\.approval_hash AND req\.questions=act\.questions/);
 assert.match(prod,/GET DIAGNOSTICS v_inserted = ROW_COUNT;\s*IF v_inserted=1 AND v_snapshot_ready THEN/);
 assert.match(prod,/cq_v4_capture_grading_snapshot_internal\(v_uid,p_chapter_uuid\)/);
 assert.match(prod,/cq_v4_record_frozen_reread_internal\(v_uid,p_chapter_uuid\)/);
});
