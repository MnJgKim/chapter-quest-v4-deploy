import fs from 'node:fs/promises';
import vm from 'node:vm';
const context=vm.createContext({window:{}});
vm.runInContext(await fs.readFile(new URL('../public/project-config.js',import.meta.url),'utf8'),context);
const config=context.window.CQ_PUBLIC_PROJECT;
const results=[];
for(const name of ['cq_v4_my_chapters','cq_v4_list_child_access','cq_v4_parent_submissions']){
 const response=await fetch(config.url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:config.anonKey,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(15000)});
 const payload=await response.json().catch(()=>({}));results.push({name:'anonymous RPC blocked: '+name,status:response.status,code:payload.code,pass:response.status===401||response.status===403});
}
for(const name of ['cq-v4-pdf-parent','cq-v4-pdf-link']){
 const response=await fetch(config.url+'/functions/v1/'+name,{method:'POST',headers:{apikey:config.anonKey,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(15000)});
 results.push({name:'missing JWT Edge request blocked: '+name,status:response.status,pass:response.status===401});
}
await fs.writeFile(new URL('./live-anonymous-results.json',import.meta.url),JSON.stringify({scope:'live anonymous requests only; no authenticated writes',checks:results},null,2));
console.log(JSON.stringify(results,null,2));if(results.some(r=>!r.pass))process.exitCode=1;
