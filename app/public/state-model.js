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
 root.CQState=Object.freeze({normalize});
})(globalThis);
