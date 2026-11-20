import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync('review/sql-candidates/cq_v4_v3b_reread_install_bundle.REVIEW-ONLY.sql','utf8');
test('transactional V3B bundle installs helpers before submit and preserves private keys',()=>{
 const order=['CREATE TABLE IF NOT EXISTS public.cq_v4_immutable_grading_snapshots','create table if not exists public.cq_v4_reread_progress','CREATE OR REPLACE FUNCTION public.cq_v4_record_frozen_reread_internal','CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers'];
 let prev=-1;for(const item of order){const pos=sql.indexOf(item);assert.ok(pos>prev,'Missing or out of order: '+item);prev=pos;}
 assert.match(sql,/^BEGIN;/m);assert.match(sql,/^COMMIT;/m);
 assert.match(sql,/END; \\$function\\$;\\s*-- Explicitly close PostgreSQL's default PUBLIC EXECUTE/,'Missing function terminator');
 assert.doesNotMatch(sql,/CREATE TRIGGER cq_v4_reread_after_submit/i);
 assert.match(sql,/REVOKE ALL ON public.cq_v4_immutable_grading_snapshots FROM PUBLIC,anon,authenticated/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public.cq_v4_record_frozen_reread_internal\(uuid,uuid\) FROM PUBLIC,anon,authenticated/);
 assert.match(sql,/cq_v4_is_released\(p_chapter_uuid,v_uid\)/);
});
