/* Stage 132: explicit student workflow separation. This is a UI boundary, NOT an RLS boundary. */
(function(root){
 'use strict';
 const MODES=Object.freeze({DEMO:'local-demo',SERVER:'server'});
 function createMode(initial=MODES.DEMO){
  if(!Object.values(MODES).includes(initial))throw Error('Invalid student mode');
  let current=initial;
  return Object.freeze({get:()=>current,set(next){if(!Object.values(MODES).includes(next))throw Error('Invalid student mode');current=next;return current},isServer:()=>current===MODES.SERVER});
 }
 function serverOnlyMarkup(){return '<section class="card"><h3>학습 순서</h3><p>내 배정 챕터를 불러오고 원문을 읽은 뒤, 문제·독후감·말하기를 완료해 제출하세요. 제출한 답변은 수정할 수 없으며 부모가 공개한 피드백을 확인할 수 있습니다.</p></section>'}
 root.CQStudentMode132=Object.freeze({MODES,createMode,serverOnlyMarkup});
 if(typeof module!=='undefined')module.exports={MODES,createMode,serverOnlyMarkup};
})(typeof window!=='undefined'?window:globalThis);
