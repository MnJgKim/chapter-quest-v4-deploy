(function(root){'use strict';
 function createSession({fetchImpl=fetch,now=()=>Date.now(),onReset=()=>{},onUpdate=()=>{}}={}){
  let current=null,epoch=0,controller=new AbortController(),refreshing=null;
  const assert=expected=>{if(expected!==epoch||!current)throw Error('STUDENT_SESSION_CHANGED');};
  function reset(){epoch++;controller.abort();controller=new AbortController();current=null;refreshing=null;onReset();}
  async function login(project,email,password){
   reset();const expected=epoch;const response=await fetchImpl(project.url+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:project.anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password}),signal:controller.signal});
   if(expected!==epoch)throw Error('STUDENT_SESSION_CHANGED');if(!response.ok)throw Error('학생 로그인 실패 ('+response.status+')');
   const data=await response.json();if(expected!==epoch)throw Error('STUDENT_SESSION_CHANGED');
   if(!data.access_token||!data.refresh_token||!data.user?.id)throw Error('학생 인증 정보가 없습니다.');
   current={token:data.access_token,refreshToken:data.refresh_token,uid:data.user.id,expiresAt:now()+(data.expires_in||3600)*1000,project:{...project}};onUpdate(current);return current;
  }
  async function token(expected=epoch){
   assert(expected);if(current.expiresAt>now()+60000)return current.token;
   if(!refreshing){
    const session=current;
    const task=(async()=>{
     try{
      const response=await fetchImpl(session.project.url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:session.project.anonKey,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refreshToken}),signal:controller.signal});
      assert(expected);if(!response.ok)throw Error('학생 로그인 시간이 만료되었습니다. 다시 로그인하세요.');
      const data=await response.json();assert(expected);
      if(!data.access_token||!data.refresh_token||data.user?.id!==session.uid)throw Error('학생 계정 갱신 정보가 일치하지 않습니다.');
      current={...session,token:data.access_token,refreshToken:data.refresh_token,expiresAt:now()+(data.expires_in||3600)*1000};onUpdate(current);return current.token;
     }catch(error){if(expected===epoch)reset();throw error;}
    })();refreshing=task;void task.finally(()=>{if(refreshing===task)refreshing=null;}).catch(()=>{});
   }
   return refreshing;
  }
  async function request(url,options={},expected=epoch){
   assert(expected);const access=await token(expected);assert(expected);
   const signal=options.signal?AbortSignal.any([controller.signal,options.signal]):controller.signal;
   const headers=new Headers(options.headers);headers.set('Authorization','Bearer '+access);
   const response=await fetchImpl(url,{...options,headers,signal});assert(expected);
   // Guard each streamed chunk without buffering large PDFs/audio before their size checks.
   if(!response.body)return response;
   const reader=response.body.getReader();
   const body=new ReadableStream({async pull(output){try{assert(expected);const part=await reader.read();assert(expected);if(part.done)output.close();else output.enqueue(part.value);}catch(error){await reader.cancel().catch(()=>{});output.error(error);}},cancel:reason=>reader.cancel(reason)});
   return new Response(body,{status:response.status,statusText:response.statusText,headers:response.headers});
  }
  return Object.freeze({login,reset,token,request,epoch:()=>epoch});
 }
 root.CQStudentSession=Object.freeze({createSession});
})(typeof window==='undefined'?globalThis:window);
