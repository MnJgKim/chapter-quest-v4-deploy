import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync('review/sql-candidates/cq_v4_submit_with_frozen_snapshot.REVIEW-ONLY.sql','utf8');
test('only verified approval provenance enters immutable reread path',()=>{
 assert.match(sql,/req\.content_hash=act\.approval_hash AND req\.questions=act\.questions/);
 assert.match(sql,/req\.parent_user_id=c\.parent_user_id/);
 assert.match(sql,/IF v_snapshot_ready THEN\s*IF NOT public\.cq_v4_capture_grading_snapshot_internal/);
 assert.match(sql,/cq_v4_record_frozen_reread_internal\(v_uid,p_chapter_uuid\)/);
 assert.match(sql,/END IF;\s*-- Existing submission is immutable/);
});
test('legacy submissions retain authorization, recording and immutable idempotency',()=>{
 assert.match(sql,/cq_v4_can_start_approved_lesson\(p_chapter_uuid,v_uid\)/);
 assert.match(sql,/bucket_id='cq-v4-speaking'/);
 assert.match(sql,/IF EXISTS \(SELECT 1 FROM public\.cq_v4_student_submissions existing/);
 assert.match(sql,/INSERT INTO public\.cq_v4_student_submissions/);
});
