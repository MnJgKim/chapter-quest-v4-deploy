/* Chapter Quest V4 stage 141: standalone, not wired to production UI. */
(function(root){
'use strict';
const DB='cq-v4-student-audio-v1', STORE='recordings', LIMIT=10*1024*1024;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MIME=new Set(['audio/webm','audio/mp4','audio/ogg']);
function key(uid,chapter){if(!UUID.test(uid)||!UUID.test(chapter))throw Error('INVALID_ID');return uid+'/'+chapter}
function openDb(indexedDBImpl=root.indexedDB){
 if(!indexedDBImpl) return Promise.reject(Error('INDEXEDDB_UNAVAILABLE'));
 return new Promise((resolve,reject)=>{
  let req;try{req=indexedDBImpl.open(DB,1)}catch{reject(Error('INDEXEDDB_OPEN_FAILED'));return}
  req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'id'})};
  req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(Error('INDEXEDDB_OPEN_FAILED'));
  req.onblocked=()=>reject(Error('INDEXEDDB_BLOCKED'));
 });
}
async function operate(db,mode,callback,canCommit=()=>true){
 return new Promise((resolve,reject)=>{
  let tx,req,result=null,settled=false;
  const fail=code=>{if(!settled){settled=true;reject(Error(code))}};
  try{tx=db.transaction(STORE,mode)}catch{fail('INDEXEDDB_TRANSACTION_FAILED');return}
  tx.oncomplete=()=>{if(!settled){settled=true;if(!canCommit())reject(Error('AUDIO_CONTEXT_STALE_AFTER_COMMIT'));else resolve(result)}};
  tx.onabort=()=>fail('INDEXEDDB_TRANSACTION_ABORTED');
  tx.onerror=()=>fail('INDEXEDDB_TRANSACTION_FAILED');
  try{req=callback(tx.objectStore(STORE))}catch{try{tx.abort()}catch{}fail('INDEXEDDB_OPERATION_FAILED');return}
  req.onsuccess=()=>{result=req.result??null};
  req.onerror=()=>fail('INDEXEDDB_OPERATION_FAILED');
 });
}
async function withDb(indexedDBImpl,action){const db=await openDb(indexedDBImpl);try{return await action(db)}finally{db.close()}}
async function hash(blob,cryptoImpl=root.crypto){if(!cryptoImpl?.subtle)throw Error('CRYPTO_UNAVAILABLE');const bytes=await blob.arrayBuffer();const digest=await cryptoImpl.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('')}
// Cross-tab mutation serialization. Fail closed when Web Locks is unavailable.
async function withAudioLock(uid,chapter,action){
 const locks=root.navigator?.locks;
 if(!locks||typeof locks.request!=='function')throw Error('AUDIO_CROSS_TAB_LOCK_UNAVAILABLE');
 const lockName='cq-v4-audio:'+encodeURIComponent(uid)+':'+encodeURIComponent(chapter);
 return locks.request(lockName,{mode:'exclusive'},async lock=>{
  if(!lock)throw Error('AUDIO_CROSS_TAB_LOCK_DENIED');
  return action();
 });
}
function createVault({indexedDBImpl=root.indexedDB,cryptoImpl=root.crypto}={}){
 return Object.freeze({
  async save(uid,chapter,blob,canCommit=()=>true,alreadyLocked=false){const id=key(uid,chapter);if(!blob||typeof blob.arrayBuffer!=='function'||!MIME.has(blob.type)||!Number.isSafeInteger(blob.size)||blob.size<1||blob.size>LIMIT)throw Error('INVALID_AUDIO');const sha256=await hash(blob,cryptoImpl);if(!canCommit())throw Error('AUDIO_CONTEXT_STALE');const commit=()=>withDb(indexedDBImpl,db=>{if(!canCommit())throw Error('AUDIO_CONTEXT_STALE');return operate(db,'readwrite',store=>{if(!canCommit())throw Error('AUDIO_CONTEXT_STALE');return store.put({id,uid,chapter,blob,sha256,mime:blob.type,size:blob.size,savedAt:Date.now()})},canCommit)});await (alreadyLocked?commit():withAudioLock(uid,chapter,commit));return {id,sha256,size:blob.size,mime:blob.type}},
  async load(uid,chapter,canRead=()=>true){const id=key(uid,chapter);if(!canRead())throw Error('AUDIO_READ_CONTEXT_STALE');const rec=await withDb(indexedDBImpl,db=>operate(db,'readonly',store=>store.get(id)));if(!canRead())throw Error('AUDIO_READ_CONTEXT_STALE');if(!rec)return null;if(rec.uid!==uid||rec.chapter!==chapter||!rec.blob||!MIME.has(rec.mime)||rec.size!==rec.blob.size||rec.size>LIMIT)throw Error('AUDIO_RECORD_INVALID');const digest=await hash(rec.blob,cryptoImpl);if(!canRead())throw Error('AUDIO_READ_CONTEXT_STALE');if(digest!==rec.sha256)throw Error('AUDIO_HASH_MISMATCH');return {blob:rec.blob,sha256:rec.sha256,mime:rec.mime,size:rec.size,savedAt:rec.savedAt}},
  async remove(uid,chapter){const id=key(uid,chapter);await withAudioLock(uid,chapter,()=>withDb(indexedDBImpl,db=>operate(db,'readwrite',store=>store.delete(id))));return true}
 });
}
const api={createVault,key,hash,withAudioLock,DB,STORE,LIMIT};if(typeof module!=='undefined'&&module.exports)module.exports=api;root.CQAudioVault=Object.freeze(api);
})(typeof window!=='undefined'?window:globalThis);
