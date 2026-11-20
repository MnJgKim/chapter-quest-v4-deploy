import test from 'node:test';
import assert from 'node:assert/strict';
import {validateDraft} from './worker.mjs';
const draft={questions:[{kind:'inference',text:'Why?',sample:'Because of the chapter.'}],vocabulary:[],writingPrompt:'Write.',speakingPrompt:'Speak.'};
test('unsupported model question kinds fail closed instead of becoming publishable inference',()=>{
 for(const kind of [undefined,'unexpected','<script>','',42])assert.throws(()=>validateDraft({...draft,questions:[{...draft.questions[0],kind}]}),/문제 종류/);
});
test('supported historical question labels remain accepted after strict validation',()=>{
 for(const kind of ['literal','comprehension','inference','critical','short'])assert.equal(validateDraft({...draft,questions:[{...draft.questions[0],kind}]}).questions.length,1);
});
