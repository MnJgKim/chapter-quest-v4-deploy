/* Read-only existing anonymous session probe. Never creates, refreshes, replaces or deletes Auth users. */
(function(root){
 'use strict';
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 async function inspect({project,storage,fetchImpl=fetch,now=()=>Date.now(),allowOrigin=url=>root.CQOrigin?.allows(url)??/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)}){
  if(!project?.url||!project.anonKey||!allowOrigin(project.url))return {status:'configuration'};
  let origin;try{origin=new URL(project.url);}catch{return {status:'configuration'};}if(origin.pathname!=='/'||origin.search||origin.hash||origin.username||origin.password)return {status:'configuration'};
  const ref=origin.hostname.split('.')[0],key=`sb-${ref}-auth-token`;
  let saved;try{const raw=storage.getItem(key);if(!raw)return {status:'absent'};if(raw.length>100000)return {status:'invalid'};saved=JSON.parse(raw);}catch{return {status:'unreadable'};}
  const candidate=saved?.access_token? saved : saved?.currentSession;
  const token=candidate?.access_token;if(typeof token!=='string'||token.length>20000||token.split('.').length!==3)return {status:'invalid'};
  const headers={apikey:project.anonKey,Authorization:'Bearer '+token};
  try{
   const userResponse=await fetchImpl(project.url+'/auth/v1/user',{method:'GET',headers,cache:'no-store',redirect:'error'});
   if(userResponse.status===401||userResponse.status===403)return {status:'expired'};
   if(!userResponse.ok)return {status:'unavailable'};
   const user=await userResponse.json();if(!uuid.test(user?.id||'')||user.is_anonymous!==true)return {status:'not-anonymous'};
   // JWT expiry only controls local use lifetime; getUser above is the identity authority.
   let exp;try{const payload=token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');exp=JSON.parse(atob(payload.padEnd(Math.ceil(payload.length/4)*4,'='))).exp;}catch{return {status:'invalid'};}
   if(!Number.isSafeInteger(exp)||exp*1000<=now()+5000)return {status:'expired'};
   const response=await fetchImpl(project.url+'/rest/v1/cq_v4_pdf_enrollments?select=student_user_id&student_user_id=eq.'+encodeURIComponent(user.id),{method:'GET',headers,cache:'no-store',redirect:'error'});
   if(!response.ok)return {status:'unavailable'};const rows=await response.json();
   if(!Array.isArray(rows)||rows.length!==1||rows[0].student_user_id!==user.id)return {status:'unlinked'};
   return {status:'ready',session:{uid:user.id,token,expiresAt:exp*1000}};
  }catch{return {status:'unavailable'};}
 }
 root.CQExistingStudentSession=Object.freeze({inspect});
})(globalThis);
