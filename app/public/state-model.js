(function(root){
 'use strict';
 const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
 function normalize(input,names=['서우','서진']){
  const original=object(input)?JSON.parse(JSON.stringify(input)):{};
  const state={...original};
  state.students=Array.isArray(state.students)?state.students.filter(s=>object(s)&&typeof s.name==='string'&&s.name.trim()).map(s=>({...s,active:s.active===true})):names.map((name,i)=>({name,active:i===0}));
  if(!state.students.length)state.students=names.map((name,i)=>({name,active:i===0}));
  state.books=(Array.isArray(state.books)?state.books:[]).filter(object).map(b=>({...b,students:Array.isArray(b.students)?b.students:[],chapters:(Array.isArray(b.chapters)?b.chapters:[]).filter(object).map(c=>({...c,questions:Array.isArray(c.questions)?c.questions.filter(object):[],vocabulary:Array.isArray(c.vocabulary)?c.vocabulary.filter(object):[]}))}));
  for(const key of ['records','weekly','focus'])if(!object(state[key]))state[key]={};
  for(const [key,record] of Object.entries(state.records))if(object(record)){state.records[key]={...record,answers:object(record.answers)?record.answers:{},writing:typeof record.writing==='string'?record.writing:'',speaking:typeof record.speaking==='string'?record.speaking:''};}
  if(!state.students.some(s=>s.name===state.who))state.who=state.students[0].name;
  state.code='';
  return {state,repaired:JSON.stringify(original)!==JSON.stringify(state)};
 }
 function restore(storage,key,backup,names){
  const input=backup?.state;
  if(backup?.format!=='chapter-quest-v4'||!object(input)||!Array.isArray(input.books)||!Array.isArray(input.students)||!input.students.length||!object(input.records)||!object(input.weekly)||input.books.some(b=>!object(b)||typeof b.id!=='string'||!Array.isArray(b.students)||!Array.isArray(b.chapters)||b.chapters.some(c=>!object(c)||typeof c.id!=='string'))||input.students.some(s=>!object(s)||typeof s.name!=='string'))throw Error('백업 구조가 올바르지 않습니다. 현재 기록은 변경하지 않았습니다.');
  const checked=normalize(input,names),before=storage.getItem(key);
  const recoveryKey=key+':before-restore:'+Date.now()+':'+(root.crypto?.randomUUID?.()||Math.random().toString(36).slice(2));
  if(before!==null){
   try{storage.setItem(recoveryKey,before);if(storage.getItem(recoveryKey)!==before)throw Error('verify');}
   catch{throw Error('기존 기록의 복구 사본을 저장할 수 없어 복원을 중단했습니다.');}
  }
  if(storage.getItem(key)!==before)throw Error('다른 탭에서 기록이 변경되어 복원을 중단했습니다. 최신 기록은 보존했습니다.');
  const serialized=JSON.stringify(checked.state);
  try{storage.setItem(key,serialized);if(storage.getItem(key)!==serialized)throw Error('verify');}
  catch{if(before!==null)try{if(storage.getItem(key)===serialized)storage.setItem(key,before);}catch{}throw Error('복원 저장에 실패했습니다. 기존 기록과 복구 사본을 보관하세요.');}
  return {...checked,recoveryKey:before===null?null:recoveryKey};
 }
 root.CQState=Object.freeze({normalize,restore});
})(globalThis);
