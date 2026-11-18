import {api,body,endpoint,hash,HttpError,text} from '../_shared/http.ts';
export const handler=endpoint(async(req)=>{
 const input=await body(req),code=text(input.employee_id,'Employee ID',40).toLowerCase();
 if(!/^[a-z0-9][a-z0-9._-]{1,39}$/.test(code))throw new HttpError(401,'Invalid employee ID or password.');
 if(typeof input.password!=='string'||!input.password||input.password.length>1024)throw new HttpError(401,'Invalid employee ID or password.');
 const allowed=await api('/rest/v1/rpc/allow_employee_login',{method:'POST',body:{bucket_input:await hash(code)}});
 if(!allowed)throw new HttpError(429,'Too many sign-in attempts. Try again in 15 minutes.');
 const rows=await api(`/rest/v1/employees?select=email,auth_id,active&login_key=eq.${encodeURIComponent(code)}`);
 const employee=rows.length===1&&rows[0].active?rows[0]:null;
 if(!employee?.auth_id)throw new HttpError(401,'Invalid employee ID or password.');
 try{return await api('/auth/v1/token?grant_type=password',{method:'POST',body:{email:employee.email,password:input.password}});}
 catch{throw new HttpError(401,'Invalid employee ID or password.');}
});
if(import.meta.main)Deno.serve(handler);
