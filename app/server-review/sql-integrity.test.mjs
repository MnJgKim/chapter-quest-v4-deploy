import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

const read=name=>fs.readFile(new URL(name,import.meta.url),'utf8');
const occurrences=(source,needle)=>source.split(needle).length-1;

test('weekly scheduling SQL has one complete function body and one grant',async()=>{
 const source=await read('./weekly-atomic-rpc.REVIEW.sql');
 assert.equal(occurrences(source,'create or replace function public.cq_v4_parent_schedule_week_atomic('),1);
 assert.equal(occurrences(source,'grant execute on function public.cq_v4_parent_schedule_week_atomic('),1);
 assert.ok(source.includes("act.approval_hash ~ '^([0-9a-f]{32}|[0-9a-f]{64})$'"));
 assert.ok(source.includes('jsonb_array_length(p_items)=0'));
 assert.ok(source.trimEnd().endsWith('to authenticated;'));
});

test('opening preflight has no orphaned SQL or repeated coverage query',async()=>{
 const source=await read('./opening-readiness-preflight.REVIEW.sql');
 assert.equal(occurrences(source,'-- Existing future lessons already armed by legacy release flag.'),1);
 assert.equal(occurrences(source,'-- Opening week aggregate coverage only'),1);
 assert.ok(!source.includes(';\n\n);'));
 assert.ok(source.trimEnd().endsWith('group by lesson_date order by lesson_date;'));
});
