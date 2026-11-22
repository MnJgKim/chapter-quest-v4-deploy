// Isolated contract test: exercise the actual browser publication payload validator.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../public/js/parent-app.js',import.meta.url),'utf8');
const start=source.indexOf('  function publicationPayload(c){');
const end=source.indexOf("\n  document.addEventListener('change',",start);
assert.ok(start>=0&&end>start,'publicationPayload source found');
const publicationPayload=vm.runInNewContext(source.slice(start,end)+'\npublicationPayload;',Object.create(null));
const base={questions:[{kind:'mc',text:'Synthetic question?',options:['Yes','No'],correct:0}]};
const valid=publicationPayload(base);
assert.deepEqual(Array.from(valid.answerKey),[0]);
assert.equal(valid.questions[0].options[0],'Yes');
const rejects=(name,question)=>{
  assert.throws(()=>publicationPayload({questions:[question]}),undefined,name);
  console.log('PUBLICATION_PAYLOAD_REJECTED '+name);
};
rejects('missing correct index',{kind:'mc',text:'Question?',options:['Yes','No']});
rejects('negative correct index',{kind:'mc',text:'Question?',options:['Yes','No'],correct:-1});
rejects('out of bounds correct index',{kind:'mc',text:'Question?',options:['Yes','No'],correct:2});
rejects('string correct index',{kind:'mc',text:'Question?',options:['Yes','No'],correct:'0'});
rejects('fractional correct index',{kind:'mc',text:'Question?',options:['Yes','No'],correct:0.5});
rejects('missing MC options',{kind:'mc',text:'Question?',correct:0});
rejects('missing written model answer',{kind:'inference',text:'Explain why'});
rejects('missing question text',{kind:'mc',options:['Yes','No'],correct:0});
assert.throws(()=>publicationPayload({questions:[]}),undefined,'empty questions rejected');
console.log('PARENT_PUBLICATION_PAYLOAD_ASSERTIONS_PASSED');
