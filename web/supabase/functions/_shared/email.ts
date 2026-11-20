// Provider credentials stay in Edge Function secrets. Credential/provider bodies never leave this module.
export const emailReady=()=>!!((Deno.env.get('GMAIL_USER')&&Deno.env.get('GMAIL_APP_PASSWORD'))||(Deno.env.get('RESEND_API_KEY')&&Deno.env.get('MONTME_EMAIL_FROM')));
export function safeEmailError(error:unknown){const code=String((error as {code?:string}|null)?.code||'').toUpperCase();if(code==='EAUTH'||code==='EENVELOPE')return 'Email authentication or recipient configuration was rejected. Check the Gmail app password and recipient address.';if(['ETIMEDOUT','ECONNRESET','ECONNREFUSED','ENOTFOUND'].includes(code))return 'Email provider connection failed. The delivery will be retried.';return 'Email provider could not accept this delivery. The delivery will be retried.';}
export async function sendEmail(to:string|string[],subject:string,text:string,id:string){
 const recipients=Array.isArray(to)?to:[to],gmail=Deno.env.get('GMAIL_USER'),password=Deno.env.get('GMAIL_APP_PASSWORD');
 if(gmail&&password){
   const {default:nodemailer}=await import('npm:nodemailer@7.0.11');const transport=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,auth:{user:gmail,pass:password.replaceAll(' ','')},connectionTimeout:15000,greetingTimeout:15000,socketTimeout:20000});
   try{const result=await transport.sendMail({from:{name:'Montme Admin',address:gmail},to:recipients,subject,text,messageId:`<${id}@montme.local>`});if(result.accepted?.length!==recipients.length)throw Object.assign(new Error('Recipient rejected.'),{code:'EENVELOPE'});return result.messageId;}catch(error){throw Error(safeEmailError(error));}finally{transport.close();}
 }
 const key=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('MONTME_EMAIL_FROM');if(!key||!from)throw Error('Email is not configured. Add GMAIL_USER and GMAIL_APP_PASSWORD to Supabase secrets.');
 const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json','Idempotency-Key':id},body:JSON.stringify({from,to:recipients,subject,text})});const data=await r.json();if(!r.ok)throw Error('Email provider could not accept this delivery. The delivery will be retried.');return data.id;
}
