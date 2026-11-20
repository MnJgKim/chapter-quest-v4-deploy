import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/js/student-app.js',import.meta.url),'utf8');

test('same-week past authorized lessons expose the submission history entry',()=>{
 assert.match(source,/c\.lesson_date<todaySeoul&&c\.available&&c\.is_released\?'지난 수업 확인'/);
 assert.match(source,/c\.lesson_date>todaySeoul\|\|!c\.available\|\|!c\.is_released/);
});

test('past lessons without a submission cannot be restarted',()=>{
 assert.match(source,/if\(!submitted&&c\.lesson_date!==seoulLessonDate\(\)\)throw Error/);
 assert.match(source,/const previous=await viewApi\.submission\(c\.chapter_uuid\)/);
});

test('historical feedback is never inferred from a local draft',()=>{
 assert.match(source,/const feedback=submitted\?\.feedback_released\?/);
 assert.match(source,/let rereadSuggested=!!submitted\?\.feedback_released&&/);
 assert.match(source,/const submitted=Array\.isArray\(previous\)\?previous\[0\]:previous/);
});
