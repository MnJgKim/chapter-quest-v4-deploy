(function(root){
  'use strict';
  const loopback=new Set(['127.0.0.1','localhost','[::1]']);
  function allows(value,pageUrl=root.location?.href){
    if(typeof value!=='string')return false;
    if(/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(value))return true;
    try{
      const page=new URL(pageUrl),target=new URL(value);
      return loopback.has(page.hostname)&&loopback.has(target.hostname)&&
        target.protocol==='http:'&&target.port==='54321'&&target.pathname==='/'&&
        !target.username&&!target.password&&!target.search&&!target.hash;
    }catch{return false;}
  }
  root.CQOrigin=Object.freeze({allows});
})(globalThis);
