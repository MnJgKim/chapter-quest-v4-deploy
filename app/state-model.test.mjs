import test from 'node:test';import assert from 'node:assert/strict';import './public/state-model.js';
const normalize=globalThis.CQState.normalize;
test('missing state produces a usable library',()=>{const {state}=normalize(null);assert.equal(state.who,'서우');assert.deepEqual(state.books,[]);});
test('malformed nested lists cannot crash rendering',()=>{const {state}=normalize({books:[{id:'b',chapters:[{id:'c',questions:null,vocabulary:[null]}]}],students:'broken',records:[]});assert.deepEqual(state.books[0].chapters[0].questions,[]);assert.deepEqual(state.books[0].chapters[0].vocabulary,[]);assert.deepEqual(state.records,{});});
test('existing submissions and custom metadata survive repair',()=>{const input={books:[],students:[{name:'서우',active:true}],who:'서우',records:{a:{submitted:true,answers:{0:'A'},writing:'Original essay',speaking:'Original speaking',custom:'keep'}},weekly:{},focus:{},customRoot:{keep:true}};const result=normalize(input);assert.deepEqual(result.state.records,input.records);assert.deepEqual(result.state.customRoot,input.customRoot);assert.deepEqual(input.records.a.answers,{0:'A'});});
test('invalid selected student falls back without mixing records',()=>{const {state}=normalize({books:[],students:[{name:'A',active:true}],who:'B',records:{'B::b::c':{answers:{0:'private'},writing:'B essay'}}});assert.equal(state.who,'A');assert.equal(state.records['B::b::c'].writing,'B essay');});
test('access code is excluded from persisted state',()=>assert.equal(normalize({books:[],code:'private'}).state.code,''));
const validBackup={format:'chapter-quest-v4',state:{books:[],students:[{name:'Synthetic student',active:true}],who:'Synthetic student',records:{r:{answers:{0:'Original'},writing:'Original essay',speaking:'Original script',custom:'keep'}},weekly:{},customRoot:{keep:true}}};
function memory(){const data=new Map([['state','untouched original bytes']]);return {data,getItem:key=>data.get(key)??null,setItem:(key,value)=>data.set(key,value)};}
test('malformed backup structures cannot erase the current library',()=>{
 for(const state of [{books:{}},{...validBackup.state,books:{}},{...validBackup.state,students:null},{...validBackup.state,records:[]},{...validBackup.state,books:[{id:'b',students:[],chapters:'invalid'}]}]){const store=memory();assert.throws(()=>CQState.restore(store,'state',{format:'chapter-quest-v4',state}),/백업 구조/);assert.equal(store.getItem('state'),'untouched original bytes');assert.equal(store.data.size,1);}
});
test('restore verifies a verbatim recovery copy and preserves custom metadata',()=>{
 const store=memory();const restored=CQState.restore(store,'state',validBackup);assert.equal(store.getItem(restored.recoveryKey),'untouched original bytes');assert.equal(JSON.parse(store.getItem('state')).records.r.writing,'Original essay');assert.deepEqual(restored.state.customRoot,{keep:true});assert.equal(restored.state.records.r.custom,'keep');
});
test('backup quota failure blocks restore before changing original data',()=>{
 const store=memory();store.setItem=()=>{throw Error('quota')};assert.throws(()=>CQState.restore(store,'state',validBackup),/복구 사본/);assert.equal(store.getItem('state'),'untouched original bytes');
});
test('failed restore write retains original data and its independent recovery copy',()=>{
 const store=memory(),write=store.setItem;store.setItem=(key,value)=>{if(key==='state')throw Error('quota');write(key,value)};assert.throws(()=>CQState.restore(store,'state',validBackup),/복원 저장/);assert.equal(store.getItem('state'),'untouched original bytes');assert.equal([...store.data.values()].filter(x=>x==='untouched original bytes').length,2);
});
test('restore refuses a source changed by another tab while the recovery copy is saved',()=>{
 const store=memory(),write=store.setItem;store.setItem=(key,value)=>{write(key,value);if(key!=='state')write('state','newer tab state')};assert.throws(()=>CQState.restore(store,'state',validBackup),/다른 탭/);assert.equal(store.getItem('state'),'newer tab state');
});
test('restore error recovery cannot roll back a newer concurrent write',()=>{
 const store=memory(),write=store.setItem;store.setItem=(key,value)=>{if(key==='state'){write('state','newer tab state');throw Error('quota')}write(key,value)};assert.throws(()=>CQState.restore(store,'state',validBackup),/복원 저장/);assert.equal(store.getItem('state'),'newer tab state');
});
