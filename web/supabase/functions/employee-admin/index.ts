import {emailReady,sendEmail} from '../_shared/email.ts';
import {api,authorize,body,endpoint,HttpError,text} from '../_shared/http.ts';
export const handler=endpoint(async(req)=>{
 const actor=await authorize(req,'employees.manage'),input=await body(req),id=input.id;
 const name=text(input.name,'Full name',100),employee_code=text(input.employee_code,'Employee ID',40),email=text(input.email,'Email',254).toLowerCase();
 if(!/^[a-zA-Z0-9][a-zA-Z0-9._-]{1,39}$/.test(employee_code))throw new HttpError(400,'Employee ID must be 2–40 letters/numbers, dots, underscores or hyphens.');
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw new HttpError(400,'Enter a valid employee email.');
 let old:any=null;if(id){const rows=await api(`/rest/v1/employees?id=eq.${encodeURIComponent(id)}&select=*`);old=rows[0];if(!old)throw new HttpError(404,'Employee not found.');if(old.auth_id){const owner=await api(`/rest/v1/app_admins?user_id=eq.${old.auth_id}&select=user_id`);if(owner.length)throw new HttpError(403,'The owner account cannot be changed through employee management.');}}
 const password=typeof input.password==='string'?input.password:'';
 if((!old?.auth_id||password)&& (password.length<8||password.length>128))throw new HttpError(400,'Use an initial password of 8–128 characters.');
 const roles=await api('/rest/v1/workspace_roles?select=id,name,permissions');const role=roles.find((r:any)=>r.id===input.role_id)||roles.find((r:any)=>r.name==='Employee');if(!role)throw new HttpError(400,'Select a valid role.');
 const privilegedTarget=(old&&roles.find((r:any)=>r.id===old.role_id)?.permissions.length>0)||(role.id!==old?.role_id&&role.permissions.length>0);if(privilegedTarget){const canAssign=await api('/rest/v1/rpc/has_permission',{method:'POST',token:actor.token,body:{permission_name:'roles.manage'}});if(!canAssign)throw new HttpError(403,'Role-management permission is required to manage privileged accounts.');}
 const matches=await Promise.all([api(`/rest/v1/employees?select=id&email=eq.${encodeURIComponent(email)}`),api(`/rest/v1/employees?select=id&login_key=eq.${encodeURIComponent(employee_code.toLowerCase())}`)]);if(matches.flat().some((e:any)=>e.id!==id))throw new HttpError(409,'This email or employee ID is already in use.');
 const row={name,email,employee_code,phone:typeof input.phone==='string'?input.phone.slice(0,30):'',role:typeof input.role==='string'?input.role.slice(0,80):role.name,role_id:role.id,active:input.active!==false};
 let authId=old?.auth_id,created=false;
 if(!authId){const account=await api('/auth/v1/admin/users',{method:'POST',body:{email,password,email_confirm:true,user_metadata:{employee_code}}});authId=account.id;created=true;}
 try{
   if(!created){await api(`/auth/v1/admin/users/${authId}`,{method:'PUT',body:{email,...(password?{password}:{}),ban_duration:row.active?'none':'876000h',user_metadata:{employee_code}}});}
   const result=await api(`/rest/v1/employees${id?'?id=eq.'+encodeURIComponent(id):''}`,{method:id?'PATCH':'POST',body:{...row,auth_id:authId},prefer:'return=representation'});
   let welcome_email:any=null;
   if(password){
     welcome_email={status:'blocked',message:'Email delivery is unavailable. Share sign-in instructions through your approved onboarding channel.'};
     if(emailReady())try{
       await sendEmail([email],created?'Welcome to Montme':'Your Montme password was updated',
         `Hello ${name},

Your Montme account was ${created?'created':'updated'}.

Employee ID: ${employee_code}

Contact your company admin for secure sign-in instructions. If you did not expect this change, contact your company admin immediately.`,
         'montme-welcome-'+crypto.randomUUID());
       welcome_email={status:'sent',message:'Account notice accepted by email provider. Share the temporary password separately through your approved secure channel.'};
     }catch{
       welcome_email={status:'failed',message:'The account was saved. The account notice could not be sent.'};
     }
   }
   return {employee:result[0],account_created:created,welcome_email};
 }catch(e){if(created){try{await api(`/auth/v1/admin/users/${authId}`,{method:'DELETE'});}catch{}}else if(old){try{await api(`/auth/v1/admin/users/${authId}`,{method:'PUT',body:{email:old.email,ban_duration:old.active?'none':'876000h'}});}catch{}}throw e;}
});
if(import.meta.main)Deno.serve(handler);
