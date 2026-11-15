/* Chapter Quest V4: optional authenticated cloud sync adapter.
   A Supabase user must sign in via a future auth UI; no service-role key is ever used. */
window.CQCloud = (() => {
  let config=null, accessToken=null, userId=null, beforeRequest=null, epoch=0;
  const inFlight=new Set();
  function abortInFlight(){for(const controller of inFlight)controller.abort();inFlight.clear()}
  const api=async(path,options={})=>{
    // Bind the request to the account active at invocation time.
    const requestEpoch=epoch, requestUser=userId, requestConfig=config;
    const hook=beforeRequest;
    if(!requestConfig||!requestUser||!accessToken)throw Error('클라우드 로그인이 필요합니다.');
    if(hook)await hook();
    if(epoch!==requestEpoch||userId!==requestUser||config!==requestConfig||!accessToken)
      throw Error('로그인 계정이 변경되어 이전 요청을 전송하지 않았습니다.');
    const token=accessToken;
    const controller=new AbortController();
    inFlight.add(controller);
    // The caller may provide a signal; forward its cancellation without dropping
    // our own account-switch cancellation boundary.
    const callerSignal=options.signal;
    const onCallerAbort=()=>controller.abort();
    if(callerSignal?.aborted)controller.abort();
    else callerSignal?.addEventListener('abort',onCallerAbort,{once:true});
    try{
      if(epoch!==requestEpoch||userId!==requestUser)throw Error('로그인 계정이 변경되었습니다.');
      const response=await fetch(requestConfig.url.replace(/\/$/,'')+'/rest/v1/'+path,{
        ...options,signal:controller.signal,headers:{apikey:requestConfig.anonKey,Authorization:'Bearer '+token,
          'Content-Type':'application/json',...(options.headers||{})}
      });
      if(epoch!==requestEpoch||userId!==requestUser)throw Error('로그인 계정이 변경되어 이전 응답을 폐기했습니다.');
      return response;
    }finally{
      inFlight.delete(controller);
      callerSignal?.removeEventListener('abort',onCallerAbort);
    }
  };
  function configure({url,anonKey,token,uid}){
    if(!(globalThis.CQOrigin?.allows(url)??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)))throw Error('Supabase 프로젝트 주소를 확인하세요.');
    if(!anonKey||!token||!uid)throw Error('인증 정보가 필요합니다.');
    abortInFlight();epoch++;config={url,anonKey};accessToken=token;userId=uid;
  }
  function reset(){abortInFlight();epoch++;config=null;accessToken=null;userId=null;beforeRequest=null}
  function setBeforeRequest(callback){beforeRequest=callback}
  function updateToken(token){if(!config||!userId)throw Error('로그인이 필요합니다.');accessToken=token}
  async function push(state){
    if(!userId)throw Error('클라우드 로그인이 필요합니다.');
    const owner=userId;
    const safe=JSON.parse(JSON.stringify(state));
    delete safe.code;
    const response=await api('cq_v4_snapshots?on_conflict=owner_id',{
      method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=representation'},
      body:JSON.stringify({owner_id:owner,payload:safe,updated_at:new Date().toISOString()})
    });
    if(!response.ok)throw Error('클라우드 저장 실패: '+response.status);
    return (await response.json())[0];
  }
  async function pull(){
    if(!userId)throw Error('클라우드 로그인이 필요합니다.');
    const owner=userId;
    const response=await api('cq_v4_snapshots?select=payload,updated_at&owner_id=eq.'+encodeURIComponent(owner),{method:'GET'});
    if(!response.ok)throw Error('클라우드 불러오기 실패: '+response.status);
    const rows=await response.json();
    return rows[0]||null;
  }
  async function pushIfUnchanged(current, expected){
    if(!userId)throw Error('로그인이 필요합니다.');
    const owner=userId;
    const safe=JSON.parse(JSON.stringify(current));delete safe.code;
    let response;
    if(expected===null){
      response=await api('cq_v4_snapshots',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({owner_id:owner,payload:safe,updated_at:new Date().toISOString()})});
      if(response.status===409)return {conflict:true};
    }else{
      response=await api('cq_v4_snapshots?owner_id=eq.'+encodeURIComponent(owner)+'&updated_at=eq.'+encodeURIComponent(expected),{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify({payload:safe,updated_at:new Date().toISOString()})});
    }
    if(!response.ok)throw Error('클라우드 저장 실패: '+response.status);
    const rows=await response.json();
    return rows.length?{conflict:false,snapshot:rows[0]}:{conflict:true};
  }
  return {configure,reset,setBeforeRequest,updateToken,push,pull,pushIfUnchanged};
})();
