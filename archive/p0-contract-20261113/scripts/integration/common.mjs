import {readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
export const root=new URL('../../',import.meta.url);
export class SafeError extends Error {constructor(code){super(code);this.code=code;}}
export function needed(env,name){if(!env[name])throw new SafeError('MISSING_'+name);return env[name];}
export const isMain=url=>process.argv[1]&&pathToFileURL(process.argv[1]).href===url;
export const loopback=url=>['127.0.0.1','localhost','[::1]'].includes(url.hostname);
export async function loadTarget(env=process.env){
 let target;try{target=JSON.parse(await readFile(needed(env,'CQ_TEST_TARGET_FILE'),'utf8'));}catch(error){if(error instanceof SafeError)throw error;throw new SafeError('INVALID_TARGET_FILE');}
 return validateTarget(target,env);
}
export function validateTarget(t,env){
 if(t.purpose!=='disposable-test'||t.confirmedDisposable!==true||!t.projectRef||needed(env,'CQ_TEST_CONFIRMED_PROJECT_REF')!==t.projectRef)throw new SafeError('TEST_PROJECT_NOT_CONFIRMED');
 let api,worker,app;try{api=new URL(t.supabaseUrl);worker=new URL(t.workerOrigin);app=new URL(t.appOrigin);}catch{throw new SafeError('INVALID_TARGET_URL');}
 if(api.username||api.password||api.search||api.hash||api.pathname!=='/')throw new SafeError('INVALID_TARGET_URL');
 for(const origin of [worker,app])if(origin.origin!==origin.href.replace(/\/$/,'')||origin.username||origin.password)throw new SafeError('ORIGIN_REQUIRED');
 if(t.kind==='hosted'){
  if(!/^[a-z0-9]{20}$/.test(t.projectRef)||api.origin!==`https://${t.projectRef}.supabase.co`||!t.databaseHost)throw new SafeError('PROJECT_REF_URL_MISMATCH');
 }else if(t.kind==='local'){
  if(!loopback(api)||api.protocol!=='http:'||!['127.0.0.1','localhost'].includes(t.databaseHost))throw new SafeError('LOCAL_TARGET_NOT_LOOPBACK');
 }else throw new SafeError('INVALID_TARGET_KIND');
 if(worker.protocol!=='https:'&&!(worker.protocol==='http:'&&loopback(worker)))throw new SafeError('UNSAFE_WORKER_ORIGIN');
 if(app.protocol!=='https:'&&!(app.protocol==='http:'&&loopback(app)))throw new SafeError('UNSAFE_APP_ORIGIN');
 return Object.freeze({...t,supabaseUrl:api.origin,workerOrigin:worker.origin,appOrigin:app.origin});
}
export function databaseOptions(target,env){
 let url;try{url=new URL(needed(env,'CQ_TEST_DATABASE_URL'));}catch(error){if(error instanceof SafeError)throw error;throw new SafeError('INVALID_TEST_DATABASE_URL');}
 if(!['postgres:','postgresql:'].includes(url.protocol)||url.hostname!==target.databaseHost)throw new SafeError('DATABASE_TARGET_MISMATCH');
 const user=decodeURIComponent(url.username);
 if(target.kind==='hosted'&&url.hostname!==`db.${target.projectRef}.supabase.co`&&user!==`postgres.${target.projectRef}`)throw new SafeError('DATABASE_PROJECT_ID_UNBOUND');
 if(target.kind==='local'&&!loopback(url))throw new SafeError('DATABASE_NOT_LOCAL');
 if(target.kind==='hosted'&&['disable','allow','prefer','no-verify'].includes(url.searchParams.get('sslmode')))throw new SafeError('TLS_VERIFICATION_REQUIRED');
 // Explicit verified TLS; URL SSL options may not override this.
 for(const name of ['sslmode','ssl','sslcert','sslkey','sslrootcert'])url.searchParams.delete(name);
 return {connectionString:url.href,ssl:target.kind==='hosted'?{rejectUnauthorized:true}:false,connectionTimeoutMillis:15000,statement_timeout:45000,query_timeout:60000};
}
export async function migrations(){const dir=new URL('supabase/migrations/',root);const files=(await readdir(dir)).filter(n=>/^\d+_.*\.sql$/.test(n)).sort();return Promise.all(files.map(async name=>{const source=await readFile(new URL(name,dir),'utf8');return {name,source,sha256:createHash('sha256').update(source).digest('hex')};}));}
export async function api(target,env,path,{token,method='POST',body,headers={}}={}){
 const response=await fetch(target.supabaseUrl+path,{method,redirect:'error',signal:AbortSignal.timeout(45000),headers:{apikey:needed(env,'CQ_TEST_SUPABASE_ANON_KEY'),...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...headers},...(body===undefined?{}:{body:typeof body==='string'||body instanceof Uint8Array?body:JSON.stringify(body)})});
 return response;
}
export async function rpc(target,env,token,name,args={}){const response=await api(target,env,'/rest/v1/rpc/'+name,{token,body:args});if(!response.ok)throw new SafeError('RPC_'+name.toUpperCase()+'_HTTP_'+response.status);return response.json();}
export async function runCli(task){try{await task();}catch(error){console.error(error instanceof SafeError?error.code:'INTEGRATION_FAILED_NO_SECRETS_LOGGED');process.exitCode=1;}}
export {fileURLToPath};
