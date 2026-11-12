/* Stage42 standalone client bridge. Requires a signed-in Supabase Auth session. */
(function(root){
  async function rpc({url,anonKey,getAccessToken},fn,params={}){
    if(!(globalThis.CQOrigin?.allows(url||'')??/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url||'')))throw Error('HTTPS Supabase URL required');
    if(!anonKey)throw Error('Supabase publishable/anon key required');
    const token=await getAccessToken?.();
    if(!token)throw Error('Authentication required');
    const res=await fetch(url.replace(/\/$/,'')+'/rest/v1/rpc/'+fn,{
      method:'POST',headers:{apikey:anonKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(params)
    });
    if(!res.ok){const err=await res.json().catch(()=>({}));throw Error(err.message||`RPC ${res.status}`)}
    return res.json();
  }
  root.CQInvitationAPI={
    issue:(cfg)=>rpc(cfg,'cq_v4_issue_invite'),
    claim:(cfg,code,name)=>rpc(cfg,'cq_v4_claim_invite',{p_token:code,p_student_name:name}),
    approve:(cfg,childId)=>rpc(cfg,'cq_v4_approve_child',{p_child_user_id:childId}),
    revoke:(cfg,childId)=>rpc(cfg,'cq_v4_revoke_child',{p_child_user_id:childId})
  };
})(typeof window==='undefined'?globalThis:window);
