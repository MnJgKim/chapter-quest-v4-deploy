import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('./public/js/parent-app.js',import.meta.url),'utf8');
const match=source.match(/const chaptersForBook=\(assigned,mappings,book\)=>\{[\s\S]*?\n \};/);
assert.ok(match,'book-scoped chapter selection must exist in parent app');
const chaptersForBook=vm.runInNewContext('('+match[0].replace(/^const chaptersForBook=/,'').replace(/;$/,'')+')');
const assigned=[
 {chapter_id:'a',title:'Chapter 10'},
 {chapter_id:'b',title:'Chapter 2'},
 {chapter_id:'c',title:'Chapter 1'},
 {chapter_id:'d',title:'Chapter 3'}
];
const mappings=[
 {book_id:'book-1',chapter_id:'a',chapter_number:10},
 {book_id:'book-1',chapter_id:'b',chapter_number:2},
 {book_id:'book-1',chapter_id:'c',chapter_number:1},
 {book_id:'book-2',chapter_id:'d',chapter_number:3}
];

test('book-scoped chapter ordering follows explicit numeric metadata',()=>{
 assert.deepEqual(Array.from(chaptersForBook(assigned,mappings,'book-1'),x=>x.chapter_id),['c','b','a']);
});
test('a different book never leaks into the selected book',()=>{
 assert.deepEqual(Array.from(chaptersForBook(assigned,mappings,'book-2'),x=>x.chapter_id),['d']);
});
test('unmapped chapters cannot be selected for batch booking',()=>{
 assert.equal(chaptersForBook([{chapter_id:'unmapped',title:'Chapter 1'}],mappings,'book-1').length,0);
});
test('chapter title text cannot override book membership or order',()=>{
 const changed=assigned.map(x=>({...x,title:'Chapter 999'}));
 assert.deepEqual(Array.from(chaptersForBook(changed,mappings,'book-1'),x=>x.chapter_id),['c','b','a']);
});

const conflictMatch=source.match(/const batchDateConflicts=\(student,items,releases\)=>[^;]+;/);
assert.ok(conflictMatch,'batch date conflict checker must exist');
const batchDateConflicts=vm.runInNewContext('('+conflictMatch[0].replace(/^const batchDateConflicts=/,'').replace(/;$/,'')+')');
test('batch booking rejects an existing different chapter on same student date',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'}];
 const releases=[{student_user_id:'student-1',chapter_id:'other',lesson_date:'2026-11-23'}];
 assert.equal(batchDateConflicts('student-1',items,releases).length,1);
});
test('batch booking does not reject a different student or date',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'}];
 const releases=[{student_user_id:'student-2',chapter_id:'other',lesson_date:'2026-11-23'},{student_user_id:'student-1',chapter_id:'other',lesson_date:'2026-11-24'}];
 assert.equal(batchDateConflicts('student-1',items,releases).length,0);
});

const mappingMatch=source.match(/const batchMappingChanged=\(preview,mappings\)=>[^;]+;/);
assert.ok(mappingMatch,'batch mapping validation must exist');
const batchMappingChanged=vm.runInNewContext('('+mappingMatch[0].replace(/^const batchMappingChanged=/,'').replace(/;$/,'')+')');
test('batch preview invalidates when chapter number changes',()=>{
 const preview={book:'book-1',items:[{chapter_id:'a',chapter_number:2}]};
 assert.equal(batchMappingChanged(preview,[{book_id:'book-1',chapter_id:'a',chapter_number:3}]),true);
});
test('batch preview invalidates when chapter moves to another book',()=>{
 const preview={book:'book-1',items:[{chapter_id:'a',chapter_number:2}]};
 assert.equal(batchMappingChanged(preview,[{book_id:'book-2',chapter_id:'a',chapter_number:2}]),true);
});
test('batch preview accepts unchanged book and chapter number',()=>{
 const preview={book:'book-1',items:[{chapter_id:'a',chapter_number:2}]};
 assert.equal(batchMappingChanged(preview,[{book_id:'book-1',chapter_id:'a',chapter_number:2}]),false);
});

const catalogMatch=source.match(/const validBookCatalogResponse=\(books,mappings\)=>[^;]+;/);
assert.ok(catalogMatch,'book catalog response validator must exist');
const validBookCatalogResponse=vm.runInNewContext('('+catalogMatch[0].replace(/^const validBookCatalogResponse=/,'').replace(/;$/,'')+')');
const bookId='11111111-1111-4111-8111-111111111111';
const chapterId='22222222-2222-4222-8222-222222222222';
test('book catalog accepts a valid owner-scoped mapping response',()=>{
 assert.equal(validBookCatalogResponse([{book_id:bookId,title:'Book 2'}],[{book_id:bookId,chapter_id:chapterId,chapter_number:3}]),true);
});
test('book catalog rejects malformed or missing mapping arrays',()=>{
 assert.equal(validBookCatalogResponse([{book_id:bookId,title:'Book 2'}],null),false);
 assert.equal(validBookCatalogResponse([{book_id:bookId,title:'Book 2'}],[{book_id:bookId,chapter_id:chapterId,chapter_number:'3'}]),false);
});
test('book catalog rejects mapping references to unknown books',()=>{
 assert.equal(validBookCatalogResponse([{book_id:bookId,title:'Book 2'}],[{book_id:chapterId,chapter_id:chapterId,chapter_number:3}]),false);
});

const readbackMatch=source.match(/const batchReadbackMatches=\(student,items,rows\)=>[^;]+;/);
assert.ok(readbackMatch,'batch readback validation must exist');
const batchReadbackMatches=vm.runInNewContext('('+readbackMatch[0].replace(/^const batchReadbackMatches=/,'').replace(/;$/,'')+')');
test('batch readback verifies every persisted chapter and date',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'},{chapter_id:'b',lesson_date:'2026-11-25'}];
 const rows=[{student_user_id:'s1',chapter_id:'a',lesson_date:'2026-11-23',released_at:'2026-11-17T01:00:00Z'},{student_user_id:'s1',chapter_id:'b',lesson_date:'2026-11-25',released_at:'2026-11-17T01:00:00Z'}];
 assert.equal(batchReadbackMatches('s1',items,rows),true);
 assert.equal(batchReadbackMatches('s1',items,rows.slice(0,1)),false);
});
test('batch readback rejects wrong student, date, or malformed response',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'}];
 assert.equal(batchReadbackMatches('s1',items,[{student_user_id:'s2',chapter_id:'a',lesson_date:'2026-11-23'}]),false);
 assert.equal(batchReadbackMatches('s1',items,[{student_user_id:'s1',chapter_id:'a',lesson_date:'2026-11-24'}]),false);
 assert.equal(batchReadbackMatches('s1',items,null),false);
});

test('batch readback rejects schedules that are not pre-armed for automatic release',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'}];
 assert.equal(batchReadbackMatches('s1',items,[{student_user_id:'s1',chapter_id:'a',lesson_date:'2026-11-23',released_at:null}]),false);
 assert.equal(batchReadbackMatches('s1',items,[{student_user_id:'s1',chapter_id:'a',lesson_date:'2026-11-23',released_at:'invalid'}]),false);
 assert.equal(batchReadbackMatches('s1',items,[{student_user_id:'s1',chapter_id:'a',lesson_date:'2026-11-23',released_at:'2026-11-17T01:00:00Z'}]),true);
});

test('batch booking rejects an existing same chapter on the same date',()=>{
 const items=[{chapter_id:'a',lesson_date:'2026-11-23'}];
 const releases=[{student_user_id:'student-1',chapter_id:'a',lesson_date:'2026-11-23'}];
 assert.equal(batchDateConflicts('student-1',items,releases).length,1);
});
test('batch preview reloads current chapter readiness, assignments and schedules',()=>{
 const previewStart=source.indexOf("if(b.dataset.batchAuto==='preview')");
 const previewEnd=source.indexOf("}else if(b.dataset.batchAuto==='confirm')",previewStart);
 const preview=source.slice(previewStart,previewEnd);
 assert.ok(preview.includes('await refreshPdfParentLists({requireReleases:true})'));
 assert.ok(preview.indexOf('await refreshPdfParentLists({requireReleases:true})')<preview.indexOf('const assigned='));
 assert.ok(preview.includes("await parentRpc('cq_v4_parent_list_book_chapters')"));
});

test('book management distinguishes committed mutation from failed follow-up refresh',()=>{
 const start=source.indexOf("const bookCatalogPanel=");
 const end=source.indexOf("const batchReadbackMatches=",start);
 const bookHandler=source.slice(start,end);
 assert.ok(bookHandler.includes('let mutationCommitted=false'));
 assert.ok(bookHandler.includes("await parentRpc('cq_v4_parent_create_book',{p_title:title});mutationCommitted=true;"));
 assert.ok(bookHandler.includes("await parentRpc('cq_v4_parent_link_book_chapter',{p_book_id:book,p_chapter_id:chapter,p_chapter_number:number});mutationCommitted=true;"));
 assert.ok(bookHandler.includes("mutationCommitted?'서버 변경 요청은 완료됐지만 목록 재확인에 실패했습니다."));
});

test('review-only scheduling SQL retains production parent ownership column',()=>{
 const weekly=readFileSync(new URL('./server-review/weekly-atomic-rpc.REVIEW.sql',import.meta.url),'utf8');
 const auto=readFileSync(new URL('./server-review/auto-release-week-rpc.REVIEW.sql',import.meta.url),'utf8');
 const cancel=readFileSync(new URL('./server-review/auto-release-cancel-rpc.REVIEW.sql',import.meta.url),'utf8');
 const preflight=readFileSync(new URL('./server-review/opening-readiness-preflight.REVIEW.sql',import.meta.url),'utf8');
 assert.ok(weekly.includes('(parent_user_id,student_user_id,chapter_id,lesson_date,timezone)'));
 assert.ok(weekly.includes("values(v_parent,p_student_user_id,v_chapter,v_date,'Asia/Seoul')"));
 assert.ok(auto.includes('where parent_user_id=v_parent and student_user_id=p_student_user_id'));
 assert.ok(cancel.includes('where parent_user_id=v_parent and student_user_id=p_student_user_id'));
 assert.ok(preflight.includes('s.parent_user_id=e.parent_user_id'));
});
