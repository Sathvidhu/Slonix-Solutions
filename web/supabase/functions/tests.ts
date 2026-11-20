import {handler as login} from './employee-login/index.ts';
import {handler as employeeAdmin} from './employee-admin/index.ts';
import {handler as delivery} from './deliver-notifications/index.ts';
function assert(value:unknown,message='Assertion failed'){if(!value)throw new Error(message);}
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});
const post=(body:unknown,headers:Record<string,string>={})=>new Request('https://edge.example.test/function',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
async function mocked(fn:(url:URL,request:Request)=>Response|Promise<Response>,test:()=>Promise<void>){const fetch=globalThis.fetch;Deno.env.set('SUPABASE_URL','https://database.example.test');Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','synthetic-server-key');globalThis.fetch=async(input:any,init:any)=>{const request=new Request(input,init);return await fn(new URL(request.url),request);};try{await test();}finally{globalThis.fetch=fetch;}}
Deno.test('Oversize login requests are rejected without needing a content length',async()=>{
 const req=new Request('https://edge.example.test/function',{
  method:'POST',body:JSON.stringify({employee_id:'EMP01',password:'x'.repeat(70000)}),
 });
 assert(!req.headers.has('content-length'));
 const result=await login(req);
 assert(result.status===413);
 assert(result.headers.get('Cache-Control')==='no-store');
});
Deno.test('Employee-ID login is rate-limited and does not expose account existence',async()=>{
 let authCalls=0;await mocked((url)=>{if(url.pathname.endsWith('/allow_employee_login'))return json(false);authCalls++;return json([]);},async()=>{const r=await login(post({employee_id:'EMP01',password:'test-password'}));assert(r.status===429);assert(authCalls===0);});
});
Deno.test('Employee-ID login resolves the active directory account on the server',async()=>{
 await mocked(async(url,request)=>{if(url.pathname.endsWith('/allow_employee_login'))return json(true);if(url.pathname.endsWith('/employees')){assert(url.searchParams.get('login_key')==='eq.emp_01');return json([{email:'staff@example.com',auth_id:'staff',active:true}]);}if(url.pathname.endsWith('/token')){const b=await request.json();assert(b.email==='staff@example.com');assert(b.password==='test-password');return json({access_token:'synthetic-session',user:{id:'staff'}});}throw Error('Unexpected request');},async()=>{const r=await login(post({employee_id:'EMP_01',password:'test-password'}));assert(r.status===200);assert((await r.json()).access_token==='synthetic-session');});
});
Deno.test('Employee provisioning requires a signed-in manager',async()=>{const r=await employeeAdmin(post({}));assert(r.status===401);});
Deno.test('Employee passwords go only to Auth, never to employee records',async()=>{
 let authPassword='',row:any;
 await mocked(async(url,request)=>{if(url.pathname.endsWith('/user'))return json({id:'owner'});if(url.pathname.endsWith('/has_permission'))return json(true);if(url.pathname.endsWith('/workspace_roles'))return json([{id:'employee-role',name:'Employee',permissions:[]}]);if(url.pathname==='/auth/v1/admin/users'){authPassword=(await request.json()).password;return json({id:'created-auth'});}if(url.pathname.endsWith('/employees')&&request.method==='POST'){row=await request.json();return json([{id:'created',...row}]);}if(url.pathname.endsWith('/employees'))return json([]);throw Error('Unexpected request '+url.pathname);},async()=>{const r=await employeeAdmin(post({name:'Test',employee_code:'EMP01',email:'test@example.com',password:'synthetic-password',role_id:'employee-role'},{Authorization:'Bearer synthetic-user'}));assert(r.status===200);assert(authPassword==='synthetic-password');assert(!('password'in row));assert(row.auth_id==='created-auth');});
});
Deno.test('Employee account notices never disclose the password',async()=>{
 const keys=['GMAIL_USER','GMAIL_APP_PASSWORD','RESEND_API_KEY','MONTME_EMAIL_FROM'];
 const old=keys.map(key=>Deno.env.get(key));
 Deno.env.delete('GMAIL_USER');Deno.env.delete('GMAIL_APP_PASSWORD');
 Deno.env.set('RESEND_API_KEY','synthetic-email-key');
 Deno.env.set('MONTME_EMAIL_FROM','test@example.com');
 const password='synthetic-private-password';
 let notice='';
 try{
  await mocked(async(url,request)=>{
   if(url.hostname==='api.resend.com'){notice=await request.text();return json({id:'accepted'});}
   if(url.pathname.endsWith('/user'))return json({id:'owner'});
   if(url.pathname.endsWith('/has_permission'))return json(true);
   if(url.pathname.endsWith('/workspace_roles'))return json([{id:'employee-role',name:'Employee',permissions:[]}]);
   if(url.pathname==='/auth/v1/admin/users')return json({id:'staff'});
   if(url.pathname.endsWith('/employees'))return json(request.method==='POST'?[{id:'staff'}]:[]);
   throw Error('Unexpected request '+url.pathname);
  },async()=>{
   const result=await employeeAdmin(post({name:'Test',employee_code:'EMP01',email:'staff@example.com',password,role_id:'employee-role'},{Authorization:'Bearer synthetic-user'}));
   assert(result.status===200);
   assert((await result.json()).welcome_email.status==='sent');
   assert(notice.includes('EMP01')&&!notice.includes(password));
  });
 }finally{keys.forEach((key,i)=>old[i]===undefined?Deno.env.delete(key):Deno.env.set(key,old[i]!));}
});
Deno.test('A password manager without role permission cannot take over a privileged account',async()=>{
 await mocked(async(url,request)=>{if(url.pathname.endsWith('/user'))return json({id:'limited-manager'});if(url.pathname.endsWith('/has_permission'))return json((await request.json()).permission_name==='employees.manage');if(url.pathname.endsWith('/workspace_roles'))return json([{id:'privileged',name:'Manager',permissions:['roles.manage']}]);if(url.pathname.endsWith('/app_admins'))return json([]);if(url.pathname.endsWith('/employees'))return json([{id:'target',auth_id:'target-auth',role_id:'privileged',email:'target@example.com'}]);throw Error('Unexpected write attempted');},async()=>{const r=await employeeAdmin(post({id:'target',name:'Target',employee_code:'EMP01',email:'target@example.com',password:'new-password',role_id:'privileged'},{Authorization:'Bearer synthetic-user'}));assert(r.status===403);});
});
Deno.test('Delivery records do not report success when an email recipient is rejected',async()=>{
 Deno.env.set('MONTME_DISPATCH_SECRET','synthetic-dispatch');Deno.env.set('RESEND_API_KEY','synthetic-email-key');Deno.env.set('MONTME_EMAIL_FROM','Montme <notifications@example.com>');let patch:any;
 await mocked(async(url,request)=>{if(url.pathname.endsWith('/refresh_attendance_notifications'))return json(null);if(url.pathname.endsWith('/claim_notification_deliveries'))return json([{id:'job',notification_id:'notice',channel:'email',attempts:1}]);if(url.pathname.endsWith('/notifications'))return json([{id:'notice',title:'High priority task',body:'Test',priority:'High',kind:'assignment'}]);if(url.pathname.endsWith('/notification_targets'))return json([{user_id:'staff',email:'test@example.com'}]);if(url.pathname.endsWith('/workspace_settings'))return json([{email_high_priority:true}]);if(url.pathname.endsWith('/notification_delivery_recipients')&&request.method==='POST')return json(null);if(url.pathname.endsWith('/notification_delivery_recipients')&&request.method==='GET')return json([{id:'recipient',email:'test@example.com',status:'pending',attempts:0}]);if(url.pathname.endsWith('/notification_delivery_recipients')&&request.method==='PATCH'){const b=await request.json();assert(b.last_error&&!b.last_error.includes('synthetic'));return json(null);}if(url.hostname==='api.resend.com'){assert(request.headers.get('Idempotency-Key')==='montme-notification-notice-recipient');return json({message:'Provider unavailable'},503);}if(url.pathname.endsWith('/notification_deliveries')&&request.method==='PATCH'){patch=await request.json();return json(null);}throw Error('Unexpected request '+url.pathname);},async()=>{const r=await delivery(post({},{'x-dispatch-secret':'synthetic-dispatch'}));assert(r.status===200);assert(patch.status==='retry');assert(!patch.sent_at);assert((await r.json()).sent===0);});
 Deno.env.delete('RESEND_API_KEY');Deno.env.delete('MONTME_EMAIL_FROM');Deno.env.delete('MONTME_DISPATCH_SECRET');
});
