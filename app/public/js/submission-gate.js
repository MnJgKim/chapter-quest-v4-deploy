/* Stage 157: fail-closed server-aware audio write gate. Integration candidate, not production wired. */
(function(root){'use strict';
function createSubmissionGate({verifySubmission,storage,key='cq_v4_audio_finalized_v1',isCurrent=()=>true}){
 if(typeof verifySubmission!=='function'||!storage||typeof isCurrent!=='function')throw Error('INVALID_GATE_DEPENDENCIES');
 const identity=(uid,chapter)=>uid+'/'+chapter;
 const valid=x=>/^[0-9a-f]{8}-[0-9a-f-]{27,}$/.test(String(x||''));
 const pending=new Map();
 function read(){try{const x=JSON.parse(storage.getItem(key)||'{}');return x&&typeof x==='object'&&!Array.isArray(x)?x:{}}catch{return {}}}
 function confirmedLocally(uid,chapter){return !!read()[identity(uid,chapter)]}
 function markConfirmed(uid,chapter){if(!valid(uid)||!valid(chapter))throw Error('INVALID_ID');const x=read();x[identity(uid,chapter)]={at:Date.now()};storage.setItem(key,JSON.stringify(x));if(!confirmedLocally(uid,chapter))throw Error('CONFIRMATION_NOT_DURABLE')}
 async function authorize(uid,chapter,context){
  if(!valid(uid)||!valid(chapter))return {status:'invalid'};
  if(!isCurrent(uid,chapter,context))return {status:'stale'};
  if(confirmedLocally(uid,chapter))return {status:'submitted'};
  const k=identity(uid,chapter);
  let check=pending.get(k);
  if(!check){check=Promise.resolve().then(()=>verifySubmission(uid,chapter));pending.set(k,check);void check.then(()=>{if(pending.get(k)===check)pending.delete(k)},()=>{if(pending.get(k)===check)pending.delete(k)})}
  let submitted;
  try{submitted=await check}catch{return {status:'unverified'}}
  if(!isCurrent(uid,chapter,context))return {status:'stale'};
  if(submitted===true){try{markConfirmed(uid,chapter)}catch{return {status:'confirmation_not_durable'}}return {status:'submitted'}}
  if(submitted!==false)return {status:'unverified'};
  return {status:'allowed'};
 }
 async function save(uid,chapter,blob,context,writer){
  if(typeof writer!=='function')throw Error('INVALID_WRITER');
  return root.CQAudioVault.withAudioLock(uid,chapter,async()=>{
  const decision=await authorize(uid,chapter,context);
  if(decision.status!=='allowed')return decision;
  if(!isCurrent(uid,chapter,context))return {status:'stale'};
  // This gate is not an atomic cross-tab transaction. A concurrent server
  // submission after verification still needs a server-side uniqueness rule.
  return {status:'written',result:await writer(uid,chapter,blob)};
  });
 }
 return Object.freeze({authorize,save,markConfirmed,confirmedLocally});
}
const api={createSubmissionGate};if(typeof module!=='undefined'&&module.exports)module.exports=api;root.CQSubmissionGate=Object.freeze(api);
})(typeof window!=='undefined'?window:globalThis);
