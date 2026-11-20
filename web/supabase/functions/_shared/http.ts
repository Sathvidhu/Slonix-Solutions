export class HttpError extends Error { constructor(public status:number,message:string){super(message);} }
export const response=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-dispatch-secret','Access-Control-Allow-Methods':'POST,OPTIONS'}});
export function endpoint(handler:(req:Request)=>Promise<unknown>){return async(req:Request)=>{if(req.method==='OPTIONS')return response({});if(req.method!=='POST')return response({message:'Method not allowed.'},405);try{return response(await handler(req));}catch(e){const error=e as Error;const status=e instanceof HttpError?e.status:500;return response({message:status>=500?'The company service is temporarily unavailable. Try again shortly.':error.message||'Request failed.'},status);}};}
export function configuration(){const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');if(!url||!key)throw new HttpError(503,'Server configuration is missing.');return {url,key};}
export async function api(path:string,options:{method?:string;body?:unknown;token?:string;prefer?:string}={}){const {url,key}=configuration();const r=await fetch(url+path,{method:options.method||'GET',headers:{apikey:key,Authorization:`Bearer ${options.token||key}`,'Content-Type':'application/json',...(options.prefer?{Prefer:options.prefer}:{})},body:options.body===undefined?undefined:JSON.stringify(options.body)});const text=await r.text();let data;try{data=text?JSON.parse(text):null;}catch{throw new HttpError(502,'Unexpected server response.');}if(!r.ok)throw new HttpError(r.status>=500?502:400,data?.message||data?.msg||data?.error_description||'Database request failed.');return data;}
export async function authorize(req:Request,permission:string){const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');if(!token)throw new HttpError(401,'Sign in first.');let user;try{user=await api('/auth/v1/user',{token});}catch{throw new HttpError(401,'Session expired. Sign in again.');}const allowed=await api('/rest/v1/rpc/has_permission',{method:'POST',token,body:{permission_name:permission}});if(!allowed)throw new HttpError(403,'Your role does not allow this action.');return {token,user};}
export async function body(req:Request){
 const maxBytes=65536;
 if(Number(req.headers.get('content-length')||0)>maxBytes)throw new HttpError(413,'Request too large.');
 const reader=req.body?.getReader();
 if(!reader)throw new HttpError(400,'Send a JSON object.');
 const decoder=new TextDecoder();
 let received=0,raw='';
 try{
  while(true){
   const {value,done}=await reader.read();
   if(done)break;
   received+=value.byteLength;
   if(received>maxBytes){
    await reader.cancel().catch(()=>{});
    throw new HttpError(413,'Request too large.');
   }
   raw+=decoder.decode(value,{stream:true});
  }
  raw+=decoder.decode();
 }finally{reader.releaseLock();}
 let data;
 try{data=JSON.parse(raw);}catch{throw new HttpError(400,'Invalid JSON.');}
 if(!data||typeof data!=='object'||Array.isArray(data))throw new HttpError(400,'Send a JSON object.');
 return data;
}
export function text(v:unknown,name:string,max=200){if(typeof v!=='string'||!v.trim()||v.trim().length>max)throw new HttpError(400,`${name} is required (maximum ${max} characters).`);return v.trim();}
export async function hash(v:string){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))].map(v=>v.toString(16).padStart(2,'0')).join('');}
