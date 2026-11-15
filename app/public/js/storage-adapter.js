/* Chapter Quest V4 stage130: explicit storage contract. No implicit cloud->local fallback.
   The server, not this module, must enforce parent/child authorization and RLS. */
(function(root){
'use strict';
const clone=x=>JSON.parse(JSON.stringify(x));
function requireIdentity(identity){
 if(!identity||!['parent','student'].includes(identity.role)||typeof identity.userId!=='string'||!identity.userId.trim())throw Error('Authenticated identity required');
 return Object.freeze({role:identity.role,userId:identity.userId});
}
function createStorage({mode,identity,cloud,studentApi,localStorageImpl}={}){
 const principal=requireIdentity(identity);
 if(!['cloud','local-demo'].includes(mode))throw Error('Explicit storage mode required');
 if(mode==='cloud'&&principal.role==='parent'&&(!cloud||typeof cloud.pull!=='function'||typeof cloud.pushIfUnchanged!=='function'))throw Error('Parent cloud adapter required');
 if(mode==='cloud'&&principal.role==='student'&&(!studentApi||typeof studentApi.assignedChapters!=='function'||typeof studentApi.submit!=='function'||typeof studentApi.submission!=='function'))throw Error('Student server adapter required');
 if(mode==='local-demo'&&(!localStorageImpl||typeof localStorageImpl.getItem!=='function'||typeof localStorageImpl.setItem!=='function'))throw Error('Demo storage required');
 let active=true;let sequence=0;
 const ensure=()=>{if(!active)throw Error('Storage session closed')};
 const key='cq-v4-demo:'+principal.role+':'+principal.userId;
 function localRead(){ensure();const raw=localStorageImpl.getItem(key);return raw===null?null:clone(JSON.parse(raw))}
 function localWrite(value){ensure();localStorageImpl.setItem(key,JSON.stringify(clone(value)));return {mode:'local-demo',persisted:true}}
 async function guarded(promise){ensure();const n=sequence;const result=await promise;if(!active||n!==sequence)throw Error('Session changed; response discarded');return result}
 return Object.freeze({
  mode,role:principal.role,
  close(){active=false;sequence++},
  async loadParentSnapshot(){ensure();if(principal.role!=='parent')throw Error('Parent role required');return mode==='cloud'?guarded(cloud.pull()):localRead()},
  async saveParentSnapshot(snapshot,expectedRevision){ensure();if(principal.role!=='parent')throw Error('Parent role required');if(!snapshot||typeof snapshot!=='object'||Array.isArray(snapshot))throw Error('Invalid snapshot');const safe=clone(snapshot);delete safe.code;
   if(mode==='local-demo')return localWrite(safe);
   if(expectedRevision===undefined)throw Error('Expected revision required for cloud write');
   const result=await guarded(cloud.pushIfUnchanged(safe,expectedRevision));if(result?.conflict)throw Error('Cloud revision conflict; no overwrite');return result;
  },
  async assignedChapters(){ensure();if(principal.role!=='student')throw Error('Student role required');if(mode==='cloud')return guarded(studentApi.assignedChapters());const data=localRead();return clone(data?.chapters||[])},
  async submission(chapterId){ensure();if(principal.role!=='student')throw Error('Student role required');if(typeof chapterId!=='string'||!chapterId)throw Error('Chapter ID required');if(mode==='cloud')return guarded(studentApi.submission(chapterId));return clone(localRead()?.submissions?.[chapterId]??null)},
  async submit(chapterId,answers){ensure();if(principal.role!=='student')throw Error('Student role required');if(typeof chapterId!=='string'||!chapterId)throw Error('Chapter ID required');if(!answers||typeof answers!=='object'||Array.isArray(answers))throw Error('Answers object required');if(mode==='cloud')return guarded(studentApi.submit(chapterId,clone(answers)));
   const data=localRead()||{};data.submissions??={};data.submissions[chapterId]=clone(answers);localWrite(data);return {mode:'local-demo',persisted:true};
  }
 });
}
root.CQStorage130=Object.freeze({createStorage});
if(typeof module!=='undefined'&&module.exports)module.exports={createStorage};
})(typeof window!=='undefined'?window:globalThis);
