// Targeted offline compatibility check. Does not open microphone, upload, or touch production.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const schema=JSON.parse(fs.readFileSync(new URL('./server-review/fixtures/live_schema.json',import.meta.url),'utf8'));
const source=fs.readFileSync(new URL('./public/js/audio-vault.js',import.meta.url),'utf8');
const student=fs.readFileSync(new URL('./public/js/student-app.js',import.meta.url),'utf8');
const root={};vm.runInNewContext(source,{window:root,console});
const vault=root.CQAudioVault;
const bucket=schema.buckets.find(b=>b.id==='cq-v4-speaking');
const accepted=new Set(bucket.allowed_mime_types);
test('local audio vault size ceiling matches captured hosted speaking bucket',()=>{
 assert.ok(bucket&&!bucket.public);
 assert.equal(vault.LIMIT,bucket.file_size_limit);
});
test('local audio MIME types are compatible with captured hosted bucket',()=>{
 for(const type of ['audio/webm','audio/mp4','audio/ogg']){
  assert.ok(accepted.has(type),type);
  assert.ok(source.includes("'"+type+"'"),type);
  assert.ok(student.includes("'"+type+"'"),type);
 }
});
test('student recording path and authenticated signed URL path target the same private bucket',()=>{
 assert.ok(student.includes('/storage/v1/object/sign/cq-v4-speaking/'));
 assert.ok(student.includes('navigator.mediaDevices.getUserMedia({audio:true})'));
 assert.ok(student.includes('new MediaRecorder('));
});

test('signed audio verification is bound to exact student and chapter object with token',()=>{
 assert.match(student,/signedUrl\.pathname!==['"]\/storage\/v1\/object\/sign\/cq-v4-speaking\/['"]\+uid\+['"]\/['"]\+uuid\+['"]\.['"]\+ext/);
 assert.match(student,/signedUrl\.searchParams\.has\(['"]token['"]\)/);
 assert.match(student,/signedUrl\.origin!==new URL\(project\.url\)\.origin/);
 assert.match(student,/crypto\.subtle\.digest\(['"]SHA-256['"],bytes\)/);
});
