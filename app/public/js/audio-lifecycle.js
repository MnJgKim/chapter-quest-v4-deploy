/* Chapter Quest V4 stage 150: serialized writes and final cleanup per student/chapter. */
(function(root){
'use strict';
function createAudioLifecycle(vault){
 if(!vault||typeof vault.save!=='function'||typeof vault.remove!=='function')throw Error('INVALID_VAULT');
 const tails=new Map(), versions=new Map(), finalized=new Set();
 const key=(uid,chapter)=>uid+'/'+chapter;
 function enqueue(id,work){
  const prior=tails.get(id)||Promise.resolve();
  const job=prior.catch(()=>{}).then(work);
  const tail=job.then(()=>{},()=>{});
  tails.set(id,tail);
  void tail.then(()=>{if(tails.get(id)===tail)tails.delete(id)});
  return job;
 }
 function save(uid,chapter,blob,canCommit=()=>true,alreadyLocked=false){
  const id=key(uid,chapter);
  if(finalized.has(id))return Promise.resolve({status:'finalized'});
  const version=(versions.get(id)||0)+1;versions.set(id,version);
  return enqueue(id,async()=>{
   if(finalized.has(id))return {status:'finalized'};
   if(!canCommit())return {status:'stale'};
   if(versions.get(id)!==version)return {status:'superseded',version};
   const receipt=await vault.save(uid,chapter,blob,()=>canCommit()&&!finalized.has(id)&&versions.get(id)===version,alreadyLocked);
   return {status:finalized.has(id)?'finalized':versions.get(id)===version?'saved':'superseded',version,receipt};
  });
 }
 function finalize(uid,chapter){
  const id=key(uid,chapter);
  finalized.add(id);versions.set(id,(versions.get(id)||0)+1);
  return enqueue(id,async()=>{await vault.remove(uid,chapter);return {status:'removed'};});
 }
 function invalidate(uid,chapter){const id=key(uid,chapter);versions.set(id,(versions.get(id)||0)+1)}
 function isLatest(uid,chapter,version){const id=key(uid,chapter);return !finalized.has(id)&&versions.get(id)===version}
 function isFinalized(uid,chapter){return finalized.has(key(uid,chapter))}
 return Object.freeze({save,finalize,invalidate,isLatest,isFinalized});
}
const api={createAudioLifecycle};
if(typeof module!=='undefined'&&module.exports)module.exports=api;
root.CQAudioLifecycle=Object.freeze(api);
})(typeof window!=='undefined'?window:globalThis);
