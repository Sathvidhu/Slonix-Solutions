// Provider credentials stay in Edge Function secrets. No credential bodies are logged or persisted.
export const emailReady=()=>!!((Deno.env.get('GMAIL_USER')&&Deno.env.get('GMAIL_APP_PASSWORD'))||(Deno.env.get('RESEND_API_KEY')&&Deno.env.get('MONTME_EMAIL_FROM')));
export async function sendEmail(to:string[],subject:string,text:string,id:string){
 const gmail=Deno.env.get('GMAIL_USER'),password=Deno.env.get('GMAIL_APP_PASSWORD');
 if(gmail&&password){
   const {default:nodemailer}=await import('npm:nodemailer@7.0.11');
   const transport=nodemailer.createTransport({host:'smtp.gmail.com',port:465,secure:true,auth:{user:gmail,pass:password.replaceAll(' ','')},connectionTimeout:15000,greetingTimeout:15000,socketTimeout:20000});
   try {const result=await transport.sendMail({from:{name:'Montme Admin',address:gmail},to,subject,text,messageId:`<${id}@montme.local>`});if(!result.accepted?.length)throw Error('Gmail did not accept the recipient.');return result.messageId;} finally {transport.close();}
 }
 const key=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('MONTME_EMAIL_FROM');
 if(!key||!from)throw Error('Email is not configured. Add GMAIL_USER and GMAIL_APP_PASSWORD to Supabase secrets.');
 const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json','Idempotency-Key':id},body:JSON.stringify({from,to,subject,text})});
 const data=await r.json();if(!r.ok)throw Error('Email provider rejected delivery. Check the sender configuration.');return data.id;
}
