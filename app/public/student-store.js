/* Device drafts/recovery maps: preserve damaged raw data before any replacement. */
(function(root){
 const isMap=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
 function inspect(storage,key){
  const raw=storage.getItem(key);if(raw===null)return {value:{},damaged:false,raw};
  try{const value=JSON.parse(raw);if(isMap(value))return {value,damaged:false,raw};}catch{}
  return {value:{},damaged:true,raw};
 }
 function readMap(storage,key){return inspect(storage,key).value;}
 function updateMap(storage,key,change){
  const current=inspect(storage,key);change(current.value);
  const serialized=JSON.stringify(current.value);let recoveryKey=null;
  if(current.damaged){
   recoveryKey=key+'_recovery_'+(root.crypto?.randomUUID?.()||Date.now()+'_'+Math.random().toString(36).slice(2));
   try{storage.setItem(recoveryKey,current.raw);if(storage.getItem(recoveryKey)!==current.raw)throw Error('Backup verification failed');}
   catch{throw Error('이전 임시저장 원본의 복구 사본을 보관하지 못해 덮어쓰기를 중단했습니다. 기기 저장 공간을 확인하세요.');}
  }
  storage.setItem(key,serialized);return {recovered:current.damaged,recoveryKey};
 }
 const api=Object.freeze({readMap,updateMap});root.CQStudentStore=api;
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(typeof window!=='undefined'?window:globalThis);
