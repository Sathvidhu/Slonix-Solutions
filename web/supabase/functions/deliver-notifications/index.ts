import {emailReady,sendEmail} from '../_shared/email.ts';
import {api,authorize,body,configuration,endpoint,HttpError} from '../_shared/http.ts';
let oauthCache:{token:string;expires:number}|null=null;
const b64=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
async function firebaseToken(account:any){if(oauthCache&&oauthCache.expires>Date.now())return oauthCache.token;const now=Math.floor(Date.now()/1000),encode=(v:unknown)=>b64(new TextEncoder().encode(JSON.stringify(v))),header=encode({alg:'RS256',typ:'JWT'}),claims=encode({iss:account.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600});const pkcs8=Uint8Array.from(atob(account.private_key.replace(/-----[^-]+-----|\s/g,'')),c=>c.charCodeAt(0));const key=await crypto.subtle.importKey('pkcs8',pkcs8,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);const unsigned=header+'.'+claims,signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(unsigned));const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:unsigned+'.'+b64(new Uint8Array(signature))})});if(!r.ok)throw Error('Firebase service account authorization failed.');const data=await r.json();oauthCache={token:data.access_token,expires:Date.now()+3300000};return oauthCache.token;}
export const handler=endpoint(async(req)=>{
 const dispatchSecret=Deno.env.get('MONTME_DISPATCH_SECRET');const supplied=req.headers.get('x-dispatch-secret');
 if(!dispatchSecret||supplied!==dispatchSecret)await authorize(req,'notifications.manage');
 const input=await body(req);
 if(input.action==='health')return {email:emailReady(),push:!!Deno.env.get('FIREBASE_SERVICE_ACCOUNT'),scheduler:!!dispatchSecret};
 await api('/rest/v1/rpc/refresh_attendance_notifications',{method:'POST',body:{}});
 const jobs=await api('/rest/v1/rpc/claim_notification_deliveries',{method:'POST',body:{batch_size:30}}),summary:{sent:number;blocked:number;failed:number;skipped:number}={sent:0,blocked:0,failed:0,skipped:0};
 for(const job of jobs){
   let patch:any={};
   try{
     const records=await api(`/rest/v1/notifications?id=eq.${job.notification_id}&cancelled_at=is.null&select=*`),n=records[0];
     if(!n){patch={status:'cancelled',last_error:null};}
     else{
       const targets=await api('/rest/v1/rpc/notification_targets',{method:'POST',body:{notification_input:n.id}});
       if(!targets.length){patch={status:'skipped',last_error:'No active account recipients.'};summary.skipped++;}
       else if(job.channel==='email'){
         const settings=await api('/rest/v1/workspace_settings?select=email_high_priority');
         if(!settings[0]?.email_high_priority||!emailReady()){patch={status:'blocked',last_error:'Email is disabled or unconfigured. Add GMAIL_USER and GMAIL_APP_PASSWORD in Supabase secrets.'};summary.blocked++;}
         else{
           const emails=[...new Set(targets.map((t:any)=>t.email).filter(Boolean))] as string[];
           await api('/rest/v1/notification_delivery_recipients?on_conflict=delivery_id,email',{method:'POST',prefer:'resolution=merge-duplicates',body:emails.map(email=>({delivery_id:job.id,email}))});
           const recipients=await api(`/rest/v1/notification_delivery_recipients?delivery_id=eq.${job.id}&select=*`);let failed=false,providerId:string|undefined;
           for(const recipient of recipients){if(recipient.status==='sent'||recipient.status==='failed')continue;try{providerId=await sendEmail(recipient.email,`[Montme - ${n.priority}] ${n.title}`,`${n.title}\n\n${n.body}\n\nSign in to Montme to review this notification.`, `montme-notification-${n.id}-${recipient.id}`);await api(`/rest/v1/notification_delivery_recipients?id=eq.${recipient.id}`,{method:'PATCH',body:{status:'sent',sent_at:new Date().toISOString(),provider_id:providerId,last_error:null}});}catch(error){const attempts=recipient.attempts+1;await api(`/rest/v1/notification_delivery_recipients?id=eq.${recipient.id}`,{method:'PATCH',body:{status:attempts>=8?'failed':'retry',attempts,last_error:(error as Error).message}});failed=true;}}
           const remaining=await api(`/rest/v1/notification_delivery_recipients?delivery_id=eq.${job.id}&status=in.(pending,retry,failed)&select=id`);if(failed||remaining.length)throw Error('One or more email recipients could not be sent.');
           patch={status:'sent',sent_at:new Date().toISOString(),provider_id:providerId||null,last_error:null};summary.sent++;
         }
       }else{
         const raw=Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
         if(!raw){patch={status:'blocked',last_error:'Push provider is not configured. Add FIREBASE_SERVICE_ACCOUNT in Supabase secrets.'};summary.blocked++;}
         else{
           const account=JSON.parse(raw),token=await firebaseToken(account),ids=targets.map((t:any)=>t.user_id);
           const devices=await api(`/rest/v1/push_devices?select=id,token,platform&user_id=in.(${ids.join(',')})`);
           if(!devices.length){patch={status:'skipped',last_error:'No registered push devices. In-app notification is still available.'};summary.skipped++;}
           else{
             let accepted=0;for(const device of devices){const r=await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token:device.token,...(device.platform==='web'
               ? {data:{notification_id:n.id},webpush:{headers:{Urgency:'high'}}}
               : {data:{notification_id:n.id,title:n.title,body:n.body.slice(0,500)},android:{priority:'high'}})}})});if(!r.ok){const e=await r.json();if(r.status===404||e.error?.details?.some((v:any)=>v.errorCode==='UNREGISTERED')){await api(`/rest/v1/push_devices?id=eq.${device.id}`,{method:'DELETE'});continue;}throw Error(`Push delivery failed (${r.status}).`);}accepted++;}
             patch=accepted?{status:'sent',sent_at:new Date().toISOString(),last_error:null}:{status:'skipped',last_error:'No valid push devices.'};if(accepted)summary.sent++;else summary.skipped++;
           }
         }
       }
     }
   }catch(e){const message=(e as Error).message;patch={status:job.attempts>=8?'failed':'retry',available_at:new Date(Date.now()+Math.min(3600,30*2**job.attempts)*1000).toISOString(),last_error:message};summary.failed++;}
   await api(`/rest/v1/notification_deliveries?id=eq.${job.id}&status=eq.processing`,{method:'PATCH',body:patch});
 }
 return summary;
});
if(import.meta.main)Deno.serve(handler);
