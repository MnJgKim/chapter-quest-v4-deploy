import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const edge = readFileSync('app/supabase/functions/cq-v4-pdf-link/index.ts','utf8');
const overlay = readFileSync('app/sql/approved-release-rpc-storage-overlay-v1.REVIEW-ONLY.sql','utf8');

test('PDF signer checks JWT and server-side read RPC before service-role signing', () => {
  const auth = edge.indexOf('userClient.auth.getUser()');
  const gate = edge.indexOf("userClient.rpc('cq_v4_can_read_lesson'");
  const sign = edge.indexOf("admin.storage.from('cq-v4-originals').createSignedUrl(");
  assert.ok(auth >= 0 && gate > auth && sign > gate, 'Authorization must precede signed URL issuance');
  assert.match(edge.slice(gate,sign), /canRead\s*!==\s*true/);
  assert.match(edge, /validPdfPath\(chapterRow\.storage_path,chapterRow\.parent_user_id,chapter\)/);
});

test('PDF read RPC gates new work but preserves submitted history', () => {
  const read = overlay.slice(overlay.indexOf('CREATE OR REPLACE FUNCTION public.cq_v4_can_read_lesson'));
  assert.match(read, /p_student\s*=\s*\(SELECT auth\.uid\(\)\)/);
  assert.match(read, /cq_v4_can_start_approved_lesson\(p_chapter,p_student\)/);
  assert.match(read, /cq_v4_student_submissions done/);
  assert.match(read, /cq_v4_pdf_enrollments e/);
});
