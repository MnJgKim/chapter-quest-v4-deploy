import { createGateway } from './gateway.ts';
import { createHandler, type Endpoint } from './handlers.ts';
export function serve(endpoint: Endpoint) {
 const required=(name:string)=>{const value=Deno.env.get(name);if(!value)throw new Error('Missing server setting: '+name);return value;};
 const config={url:required('SUPABASE_URL'),anonKey:required('SUPABASE_ANON_KEY'),serviceKey:required('SUPABASE_SERVICE_ROLE_KEY'),origin:required('APP_ORIGIN')};
 Deno.serve(createHandler(endpoint,createGateway(config),config.origin));
}
