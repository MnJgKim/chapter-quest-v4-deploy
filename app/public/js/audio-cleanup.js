/* Chapter Quest V4 stage 156: cross-session serialized cleanup, deduplicated by account/chapter. */
(function(root){'use strict';
function createCleanupQueue({storage,verifySubmission,removeAudio,isCurrent=()=>true,key='cq_v4_audio_cleanup_v1',now=()=>Date.now()}){
 if(!storage||typeof verifySubmission!=='function'||typeof removeAudio!=='function'||typeof isCurrent!=='function')throw Error('INVALID_CLEANUP_DEPENDENCIES');
 const valid=x=>/^[0-9a-f]{8}-[0-9a-f-]{27,}$/.test(String(x||''));
 const id=(uid,chapter)=>uid+'/'+chapter;
 const active=new Map(), tails=new Map();
 function read(){try{const v=JSON.parse(storage.getItem(key)||'{}');return v&&typeof v==='object'&&!Array.isArray(v)?v:{}}catch{return {}}}
 function write(all){storage.setItem(key,JSON.stringify(all));}
 function pending(uid,chapter){return valid(uid)&&valid(chapter)&&!!read()[id(uid,chapter)];}
 function mark(uid,chapter){if(!valid(uid)||!valid(chapter))throw Error('INVALID_ID');const all=read();all[id(uid,chapter)]={uid,chapter,at:now()};write(all);if(!pending(uid,chapter))throw Error('CLEANUP_INTENT_NOT_PERSISTED');return true;}
 function forget(uid,chapter){if(!valid(uid)||!valid(chapter))throw Error('INVALID_ID');const all=read();delete all[id(uid,chapter)];write(all);}
 async function reconcileOnce(uid,chapter,context){
  const current=()=>isCurrent(uid,chapter,context);
  if(!pending(uid,chapter))return {status:'none'};
  if(!current())return {status:'stale'};
  // Direct submission has already received an authoritative server success.
  // Recovery must independently verify the submission; both paths share the
  // same per-chapter in-flight task and serialized delete lifecycle.
  let confirmed=!!context?.serverConfirmed;
  if(!confirmed){
   try{confirmed=await verifySubmission(uid,chapter)}catch{return {status:'verification_failed'}}
  }
  if(!current())return {status:'stale'};
  if(!confirmed)return {status:'unconfirmed'};
  // Re-check immediately before starting the irreversible asynchronous deletion.
  if(!current())return {status:'stale'};
  try{await removeAudio(uid,chapter)}catch(error){return {status:'retry',reason:error?.name||'DELETE_FAILED'}}
  // A session may change while deletion is in flight. Never update the new UI
  // or clear its retry intent; the underlying delete cannot be canceled here.
  if(!current())return {status:'stale_after_delete'};
  try{forget(uid,chapter)}catch{return {status:'cleaned_intent_pending'}}
  return {status:'cleaned'};
 }
 function reconcile(uid,chapter,context){
  const k=id(uid,chapter)+'/'+String(context?.generation??'none');
  if(active.has(k))return active.get(k);
  // Serialize across ALL login generations for the same account/chapter.
  // New sessions must not delete while an older session's delete is in flight.
  const identity=id(uid,chapter);
  const prior=tails.get(identity)||Promise.resolve();
  const task=prior.catch(()=>{}).then(()=>reconcileOnce(uid,chapter,context));
  const tail=task.then(()=>{},()=>{});
  tails.set(identity,tail);
  active.set(k,task);
  void tail.then(()=>{if(tails.get(identity)===tail)tails.delete(identity);if(active.get(k)===task)active.delete(k)});
  return task;
 }
 return Object.freeze({mark,pending,forget,reconcile});
}
const api={createCleanupQueue};if(typeof module!=='undefined'&&module.exports)module.exports=api;root.CQAudioCleanupQueue=Object.freeze(api);
})(typeof window!=='undefined'?window:globalThis);
