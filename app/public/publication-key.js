/* A publication request belongs to account/content, not an in-memory login session. */
(function(root){
 const prefix='cq_v4_approval_request_v1:',uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 function resolve({storage,origin,uid,bookId,chapterId,pdfUuid,hash,newUUID=()=>root.crypto.randomUUID()}){
  const scope=[origin,uid,bookId,chapterId,pdfUuid,hash],key=prefix+JSON.stringify(scope);
  const valid=value=>{if(!uuid.test(value||''))throw Error('서버 승인 요청 키가 손상되었습니다. 임의로 재발급하지 않습니다.');return value;};
  const current=storage.getItem(key);if(current!==null)return valid(current);
  const prior=new Set(),ownerPrefix=origin+'|'+uid+'|';
  for(let i=0;i<storage.length;i++){
   const oldKey=storage.key(i);if(!oldKey?.startsWith(prefix))continue;
   let old;try{old=JSON.parse(oldKey.slice(prefix.length));}catch{continue;}
   if(!Array.isArray(old)||old.length!==5||typeof old[0]!=='string'||!old[0].startsWith(ownerPrefix)||!/^\d+$/.test(old[0].slice(ownerPrefix.length)))continue;
   if(old.slice(1).every((value,j)=>value===scope[j+2]))prior.add(valid(storage.getItem(oldKey)));
  }
  if(prior.size>1)throw Error('같은 자료의 기존 요청 키가 여러 개입니다. 중복 게시를 막기 위해 서버 게시 상태 확인이 필요합니다.');
  const value=prior.size?[...prior][0]:valid(newUUID());storage.setItem(key,value);
  if(storage.getItem(key)!==value)throw Error('서버 승인 요청 키를 이 기기에 보관하지 못했습니다.');
  return value;
 }
 const api=Object.freeze({resolve});root.CQPublicationKey=api;
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
