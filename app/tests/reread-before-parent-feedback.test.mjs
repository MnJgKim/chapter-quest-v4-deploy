import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const app=readFileSync('app/public/js/student-app.js','utf8');
const sql=readFileSync('app/sql/development-reread-progress-not-for-production.sql','utf8');
test('student sees required reread before feedback release',()=>{
 assert.match(app,/let rereadSuggested=!!submitted&&!!rereadProgress\?\.required&&!rereadProgress\.completed/);
 assert.match(app,/data-child="reread-complete"/);
 assert.match(app,/await api\.completeReread\(c\.chapter_uuid\)/);
 assert.match(app,/const feedback=submitted\?\.feedback_released\?/);
});
test('parent feedback entry and release are blocked until reread completion',()=>{
 const start=sql.indexOf('create or replace function public.cq_v4_release_feedback(');
 const end=sql.indexOf('-- Parent-only status',start);
 assert.ok(start>=0&&end>start);
 const rpc=sql.slice(start,end);
 assert.match(rpc,/if exists\(\s*select 1 from public\.cq_v4_reread_progress r/);
 assert.match(rpc,/r\.required=true\s*and r\.completed_at is null/);
 assert.doesNotMatch(rpc,/if p_release and exists\(/);
 assert.match(rpc,/raise exception 'Reread must be completed before parent feedback'/);
});
