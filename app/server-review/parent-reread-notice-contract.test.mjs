import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('./parent-reread-notice-rpcs.REVIEW.sql',import.meta.url),'utf8');
const ui=readFileSync(new URL('../public/js/parent-app.js',import.meta.url),'utf8');
test('notice draft is parent-scoped, idempotent and private',()=>{
 assert.match(sql,/UNIQUE\(chapter_uuid,student_user_id\)/);
 assert.match(sql,/ON CONFLICT ON CONSTRAINT cq_v4_parent_reread_notice_once DO NOTHING/);
 assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
 assert.match(sql,/REVOKE ALL ON public\.cq_v4_parent_reread_notices FROM PUBLIC, anon, authenticated/);
 assert.match(sql,/auth\.uid\(\) IS NULL OR NOT public\.cq_is_admin\(\)/);
 assert.match(sql,/c\.parent_user_id=auth\.uid\(\)/);
 assert.match(sql,/GET DIAGNOSTICS v_updated = ROW_COUNT/);
 assert.match(sql,/RETURN v_updated>0/);
});
test('notice UI does not display fabricated multiple-choice score',()=>{
 assert.match(sql,/NULL::integer AS correct_mc, NULL::integer AS total_mc/);
 assert.match(ui,/재독서 필요 \(객관식 세부 점수 미제공\)/);
 assert.match(ui,/n\.correct_mc===null&&n\.total_mc===null/);
});
