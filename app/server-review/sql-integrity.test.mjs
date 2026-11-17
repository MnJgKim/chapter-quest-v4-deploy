import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

const read=name=>fs.readFile(new URL(name,import.meta.url),'utf8');

test('weekly scheduling SQL has one complete function body and one grant',async()=>{
 const source=await read('./weekly-atomic-rpc.REVIEW.sql');
 assert.equal((source.match(/create or replace function public\\.cq_v4_parent_schedule_week_atomic\\(/g)||[]).length,1);
 assert.equal((source.match(/grant execute on function public\\.cq_v4_parent_schedule_week_atomic\\(/g)||[]).length,1);
 assert.match(source,/act\\.approval_hash ~ '\\^\\(\\[0-9a-f\\]\\{32\\}\\|\\[0-9a-f\\]\\{64\\}\\)\\$'/);
 assert.match(source,/jsonb_array_length\\(p_items\\)=0/);
 assert.match(source,/grant execute[^;]+;\\s*$/);
});

test('opening preflight has no orphaned SQL or repeated coverage query',async()=>{
 const source=await read('./opening-readiness-preflight.REVIEW.sql');
 assert.equal((source.match(/-- Existing future lessons already armed by legacy release flag\\./g)||[]).length,1);
 assert.equal((source.match(/-- Opening week aggregate coverage only/g)||[]).length,1);
 assert.doesNotMatch(source,/;\\s*\\);/);
 assert.match(source,/group by lesson_date order by lesson_date;\\s*$/);
});
