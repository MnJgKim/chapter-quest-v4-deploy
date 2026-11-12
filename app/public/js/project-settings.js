window.CQProject=Object.freeze({read(){
 try {const saved=JSON.parse(localStorage.getItem('cq_v4_cloud_project')||'null');if(saved?.url&&saved?.anonKey&&CQOrigin.allows(saved.url))return saved;}catch{}
 return window.CQ_PUBLIC_PROJECT?.url&&window.CQ_PUBLIC_PROJECT?.anonKey&&CQOrigin.allows(window.CQ_PUBLIC_PROJECT.url)?{...window.CQ_PUBLIC_PROJECT}:null;
}});
