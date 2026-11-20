import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/js/student-app.js',import.meta.url),'utf8');
test('submitted history can retry original PDF without editable form',()=>{
 assert.match(source,/const uuid=form\?\.dataset\.uuid\|\|detail\?\.dataset\.viewChapter/);
 assert.match(source,/if\(!session\|\|!uuid\|\|!chapters\.some\(c=>c\.chapter_uuid===uuid\)\)throw Error/);
 assert.match(source,/await loadServerPdf\(uuid,session\.uid,childGeneration\)/);
});
test('completed lesson does not reopen editable form',()=>{
 assert.match(source,/detail\.dataset\.viewChapter=c\.chapter_uuid/);
 assert.match(source,/if\(!submitted\)await restoreDurableVoice/);
});
