// Offline PDF transport contract: no student login, signed URLs, or network requests.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');
const transport=read('../public/js/pdf-transport.js');
const student=read('../public/js/student-app.js');
const fixture=JSON.parse(read('./fixtures/live_schema.json'));
test('student PDF is brokered by authenticated Edge Function, not a direct Storage list policy',()=>{
 assert.match(student,/CQServerPDF\.createPdfTransport/);
 assert.match(transport,/cq-v4-pdf-link/);
 assert.match(transport,/Authorization:'Bearer '\+token/);
 assert.match(transport,/method:'POST'/);
});
test('signed PDF URLs are constrained to the private original bucket, same origin and chapter',()=>{
 const bucket=fixture.buckets.find(x=>x.id==='cq-v4-originals');
 assert.ok(bucket&&!bucket.public);
 assert.ok(bucket.allowed_mime_types.includes('application/pdf'));
 assert.equal(bucket.file_size_limit,50*1024*1024);
 assert.match(transport,/signed\.origin!==base\.origin/);
 assert.match(transport,/\/storage\/v1\/object\/sign\/cq-v4-originals\//);
 assert.match(transport,/PDF_OBJECT_MISMATCH/);
 assert.match(transport,/UNSIGNED_PDF_URL/);
 assert.match(transport,/INVALID_PDF_LINK_EXPIRY/);
 assert.match(transport,/const maxPdfBytes=50\*1024\*1024/);
});
test('PDF transport fails closed on missing access or invalid signed link',()=>{
 for(const code of ['STUDENT_LOGIN_REQUIRED','PDF_ACCESS_DENIED_OR_UNAVAILABLE','PDF_LINK_NOT_AVAILABLE','UNTRUSTED_PDF_URL','PDF_DOWNLOAD_FAILED']){
  assert.ok(transport.includes(code),code);
 }
});
