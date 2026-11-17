import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('./public/js/parent-app.js',import.meta.url),'utf8');
const match=source.match(/const chapterOrder=title=>\{[\s\S]*?\n    \};/);
assert.ok(match,'chapterOrder function must exist in parent app');
const chapterOrder=vm.runInNewContext('('+match[0].replace(/^const chapterOrder=/,'').replace(/;$/,'')+')');

test('production Chapter N titles sort numerically',()=>{
 const titles=['Chapter 10 : One Mystery Solved','Chapter 2 : Leaving Again','Chapter 1 : The Dark Woods'];
 const sorted=titles.sort((a,b)=>chapterOrder(a).chapter-chapterOrder(b).chapter);
 assert.deepEqual(sorted,['Chapter 1 : The Dark Woods','Chapter 2 : Leaving Again','Chapter 10 : One Mystery Solved']);
});
test('book-chapter labels preserve book and chapter order',()=>{
 assert.equal(chapterOrder('2-3').book,2);
 assert.equal(chapterOrder('2-3').chapter,3);
 assert.equal(chapterOrder('2-10').chapter,10);
});
test('ambiguous titles are rejected rather than guessed',()=>{
 for(const title of ['Chapter X','Chapter','Book Two',''])assert.equal(chapterOrder(title),null);
});
test('chapter-only and book-chapter formats are distinguishable',()=>{
 assert.equal(chapterOrder('Chapter 3 : Across the Bridge').format,'chapter-only');
 assert.equal(chapterOrder('2-3').format,'book-chapter');
});
