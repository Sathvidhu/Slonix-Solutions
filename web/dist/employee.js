import {Repository} from './api.js';
import {workbook} from './xlsx.js';
import {enableWebPush,disableWebPush,webPushEnabled} from './employee-push.js';

const root=document.querySelector('#employee-app');
const dialog=document.querySelector('#employee-dialog');
const status=document.querySelector('#employee-status');
const repo=new Repository();
repo.authStorageKey += '.employee';
try { repo.session=JSON.parse(sessionStorage.getItem(repo.authStorageKey)||'null'); }
catch { repo.session=null; }

const tz='Asia/Kolkata';
const pages={
  Today:'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  Leads:'M3 5h18v14H3z M7 10h10 M7 14h6',
  Calls:'M5 3l4 1 1 5-2 2a13 13 0 0 0 5 5l2-2 5 1 1 4a2 2 0 0 1-2 2A18 18 0 0 1 3 5a2 2 0 0 1 2-2z',
  Reports:'M4 20V4 M4 20h16 M8 16v-5 M13 16V8 M18 16V5',
  Work:'M5 5h14v16H5z M9 3h6v5H9z M9 13h6 M9 17h6',
  Settings:'M4 6h16 M4 12h16 M4 18h16 M8 4v4 M15 10v4 M10 16v4'
};
const brand='<span class="workspace-logo" role="img" aria-label="Montme"></span>';
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const dateTime=value=>value?new Intl.DateTimeFormat('en-IN',{timeZone:tz,dateStyle:'medium',timeStyle:'short'}).format(new Date(value)):'';
const workDate=value=>new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
const duration=seconds=>seconds>=3600?`${Math.floor(seconds/3600)}h ${Math.floor(seconds%3600/60)}m`:`${Math.floor(seconds/60)}m ${Math.floor(seconds%60)}s`;
const button=(text,action,primary=false,id='')=>`<button class="btn ${primary?'primary':''}" data-action="${action}" data-id="${escape(id)}">${text}</button>`;
const table=(columns,rows)=>rows.length?`<div class="table-wrap"><table><thead><tr>${columns.map(c=>`<th scope="col">${c}</th>`).join('')}</tr></thead><tbody>${rows.map(r=>`<tr>${r.map(v=>`<td>${v}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`:'<p class="muted">No records yet.</p>';
const safeLink=value=>{try{const url=new URL(value);return ['https:','http:'].includes(url.protocol)?url.href:null;}catch{return null;}};
const rpc=(name,body={})=>repo.request('/rest/v1/rpc/'+name,{method:'POST',body});
let data=null, view=location.hash==='#notifications'?'Notifications':'Today', busy=false, loading, timer;
let pushReady=false, lastMarkup, lastSync;
let leadSearch='', leadStatus='', callDay='', leadWritesAvailable;
const leadStatuses=['New','Contacted','Interested','Follow-up','Won','Not interested'];
const outcomes=['Not reviewed','Interested','Follow-up','No answer','Busy','Wrong number','Not interested','Converted'];
const options=(values,selected)=>values.map(value=>`<option ${value===selected?'selected':''}>${escape(value)}</option>`).join('');
const localTime=value=>value?new Date(Date.parse(value)+19800000).toISOString().slice(0,16):'';
const isoTime=value=>value?new Date(value+':00+05:30').toISOString():null;
const visibleCalls=()=>calls().filter(c=>!callDay||workDate(c.started_at)===callDay);
const current=()=>data?.shifts.find(s=>!s.ended_at);
const calls=()=>data.calls;
const notifications=()=>data.notifications.filter(n=>!n.cancelled_at&&Date.parse(n.available_at)<=Date.now());
const read=id=>data.notificationReceipts.some(r=>r.notification_id===id&&r.read_at);

function announce(message){
  status.textContent=message;
  clearTimeout(announce.timer);
  announce.timer=setTimeout(()=>status.textContent='',5000);
}

async function load(){
  if(loading)return loading;
  loading=(async()=>{
    const user=repo.session?.user?.id;
    if(!user)throw Error('Sign in to your workspace.');
    const [employee]=await repo.request('/rest/v1/employees?select=*&active=eq.true&auth_id=eq.'+encodeURIComponent(user));
    if(!employee)throw Error('Your employee account is inactive. Contact your admin.');
    const own='&employee_id=eq.'+employee.id;
    const queries={
      shifts:['shift_records',own+'&order=started_at.desc'],
      calls:['call_records',own+'&order=started_at.desc'],
      contacts:['contacts','&assigned_employee_id=eq.'+employee.id+'&order=name'],
      assignments:['assignments','&recipient_ids=cs.{'+employee.id+'}&state=eq.published&release_at=lte.now()&order=release_at.desc'],
      content:['content_items',''],
      receipts:['assignment_receipts',own],
      notifications:['notifications',own+'&audience=eq.employee&order=available_at.desc'],
      notificationReceipts:['notification_receipts','&user_id=eq.'+user],
      exits:['early_exit_requests',own],
      settings:['workspace_settings',''],
      submissions:['work_submissions',own+'&order=created_at.desc'],
    };
    const entries=await Promise.all(Object.entries(queries).map(async ([key,[table,filter]])=>[
      key,await repo.request(`/rest/v1/${table}?select=*${filter}`)
    ]));
    const reports=await repo.loadDailyReports(own);
    const contacts=Object.fromEntries(entries).contacts;
    if(leadWritesAvailable!==true){
      leadWritesAvailable=contacts.some(contact=>Object.hasOwn(contact,'created_by_employee'));
      if(!contacts.length){
        try{
          await repo.request('/rest/v1/contacts?select=created_by_employee&limit=0');
          leadWritesAvailable=true;
        }catch(error){
          if(!['42703','PGRST204'].includes(error.code))throw error;
        }
      }
    }
    data={employee,reports,...Object.fromEntries(entries)};
    lastSync=new Date();
  })().finally(()=>loading=null);
  return loading;
}

function loginScreen(message=''){
  clearInterval(timer);
  data=null;
  lastMarkup=null;
  leadSearch=leadStatus=callDay='';
  root.innerHTML=`<main class="workspace-signin">
    <aside class="signin-brand">${brand}</aside>
    <section class="signin-content"><div class="signin-form">
      <h1>Employee sign in</h1>
      <p>Use your employee ID or company email to open your workspace.</p>
      <form id="employee-login">
        <div class="fields">
          <label>Employee ID or email<input name="login" required autocomplete="username"></label>
          <label>Password<input name="password" type="password" required autocomplete="current-password"></label>
        </div>
        <p class="error" role="alert">${escape(message)}</p>
        <button class="btn primary">Sign in <span aria-hidden="true">→</span></button>
      </form>
    </div></section>
  </main>`;
  const form=root.querySelector('form');
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    const values=new FormData(form);
    const login=values.get('login').trim(),password=values.get('password');
    status.textContent='';
    const submit=form.querySelector('button');
    submit.disabled=true;
    try{
      const email=login.includes('@');
      const session=await repo.request(email?'/auth/v1/token?grant_type=password':'/functions/v1/employee-login',
        {method:'POST',body:email?{email:login,password}:{employee_id:login,password}});
      repo.storeSession(session);
      await start();
    }catch(error){
      await repo.logout();
      form.querySelector('.error').textContent=error.message;
      submit.disabled=false;
    }
  });
}

function eligibleAt(shift){
  const schedule=data.employee.clock_out_time;
  return schedule?Date.parse(`${workDate(shift.started_at)}T${schedule.slice(0,5)}:00+05:30`):Date.parse(shift.started_at)+7200000;
}

function today(){
  const shift=current();
  const pause=shift?.breaks.at(-1);
  const onBreak=pause&&!pause.end;
  const early=data.exits.find(r=>r.device_shift_id===shift?.device_shift_id);
  const available=repo.attendanceAvailable;
  const canLeave=shift&&(Date.now()>=eligibleAt(shift)||early?.status==='approved');
  const day=workDate(Date.now());
  const todaysCalls=calls().filter(c=>workDate(c.started_at)===day);
  const due=data.contacts.filter(c=>c.follow_up_at&&Date.parse(c.follow_up_at)<=Date.now())
    .sort((a,b)=>Date.parse(a.follow_up_at)-Date.parse(b.follow_up_at));
  const openWork=data.assignments.filter(a=>!data.receipts.some(r=>r.assignment_id===a.id&&r.status==='completed'));
  return `<section class="card hero"><div><h2>${shift?(onBreak?'On break':'Clocked in'):'Ready to clock in?'}</h2>
    <p>${shift?'Started '+dateTime(shift.started_at):'Start a shift to record your work time.'}</p>
    ${!available?'<p>Clock-in, breaks and clock-out become available after the company upgrades its backend.</p>':shift&&!canLeave?`<p>Clock-out opens ${dateTime(eligibleAt(shift))} IST${early?` &middot; Request ${escape(early.status)}`:''}</p>`:''}</div>
    <div class="actions">${!available?'':shift?`${button(onBreak?'Resume work':'Start break','break')}
    ${canLeave?button('Clock out','clock-out',true):early?'':button('Request early clock-out','early')}`:
    '<button class="btn on-dark" data-action="clock-in">Clock in</button>'}</div></section>
    <div class="metrics">${[['Business calls today',todaysCalls.length],['Call time today',duration(todaysCalls.reduce((n,c)=>n+c.duration_seconds,0))],['Open assignments',openWork.length]]
      .map(([label,value])=>`<section class="card metric"><span class="muted">${label}</span><strong>${value}</strong></section>`).join('')}</div>
    <section class="card"><h2>Follow-ups due</h2>
    ${due.length?table(['Lead','Due',''],due.map(c=>[escape(c.name),dateTime(c.follow_up_at),
      `<div class="actions">${button('Edit lead','edit-lead',false,c.id)}${button('Complete follow-up','complete-follow-up',false,c.id)}</div>`])):
      '<p class="muted">No follow-ups are due.</p>'}</section>
    <section class="card"><h2>Recent shifts</h2>${table(['Clock in','Clock out','Breaks'],data.shifts.slice(0,7).map(s=>[
      dateTime(s.started_at),s.ended_at?dateTime(s.ended_at):'In progress',s.breaks.length]))}</section>`;
}

function leads(){
  const q=leadSearch.toLocaleLowerCase();
  const leads=data.contacts.filter(c=>(!leadStatus||c.status===leadStatus)&&
    [c.name,c.institution,c.company,c.phone,c.notes].some(v=>String(v||'').toLocaleLowerCase().includes(q)));
  return `<section class="card">
    <div class="actions section-tools">
      ${leadWritesAvailable?`${button('Add lead','new-lead',true)}${button('Bulk add leads','bulk-leads')}`:
      '<p class="muted">Lead creation requires the company backend upgrade.</p>'}
    </div>
    <form class="filters" data-filter="leads">
      <label>Search leads<input name="search" type="search" value="${escape(leadSearch)}" placeholder="Name, institution or phone"></label>
      <label>Status<select name="status"><option value="">All statuses</option>${options(leadStatuses,leadStatus)}</select></label>
      <button class="btn">Apply filters</button>
    </form>
    ${table(['Lead','Institution','Phone','Status','Follow-up',''],leads.map(c=>[
      escape(c.name),escape(c.institution||c.company),escape(c.phone),escape(c.status),dateTime(c.follow_up_at),
      `<div class="actions">${button('Edit lead','edit-lead',false,c.id)}
      ${c.follow_up_at?button('Complete follow-up','complete-follow-up',false,c.id):''}</div>`]))}</section>`;
}
function callList(){
  return `<section class="card"><div class="actions section-tools">${button('Log a call','log-call',true)}
    ${button('Export calls to Excel','export-calls')}</div>
    <form class="filters" data-filter="calls"><label>Call date (IST)<input name="day" type="date" value="${escape(callDay)}"></label>
    <button class="btn">Apply filter</button>${callDay?`<button class="btn" type="button" data-action="clear-call-filter">All dates</button>`:''}</form>
    ${table(['Time','Lead','Phone','Direction','Duration','Outcome','Notes',''],visibleCalls().map(c=>[
      dateTime(c.started_at),escape(c.lead_name||data.contacts.find(l=>l.id===c.contact_id)?.name),
      escape(c.phone),escape(c.direction),duration(c.duration_seconds),escape(c.outcome),escape(c.notes),
      leadWritesAvailable?button('Edit outcome','review-call',false,c.id):'']))}</section>`;
}
function reports(){
  return `<section class="card"><h2>Call activity</h2>
    <p>${calls().length} saved calls &middot; ${duration(calls().reduce((total,c)=>total+c.duration_seconds,0))} of call time</p>
    ${button('Export all calls to Excel','export-all-calls')}</section>
    <section class="card"><h2>Submitted Daily Work Reports</h2>
    ${!repo.attendanceAvailable?'<p class="muted">Daily Work Reports require the company backend upgrade.</p>':table(['Work date (IST)','Clock in','Clock out','Business calls',''],data.reports.map(r=>[
    escape(r.work_day),dateTime(r.started_at),dateTime(r.ended_at),r.calls.length,
    `<div class="actions">${button('View report','report',false,r.id)}${button('Download Excel','export-report',false,r.id)}</div>`]))}</section>`;
}
function work(){
  return `<div class="stack">${data.assignments.map(a=>{
    const items=(a.content_ids||[]).map(id=>data.content.find(c=>c.id===id)).filter(Boolean);
    const receipt=data.receipts.find(r=>r.assignment_id===a.id);
    return `<article class="card"><span class="tag">${receipt?.status==='completed'?'Completed':escape(a.priority)}</span>
      <h2>${escape(a.title)}</h2><p class="body-text">${escape(a.message)}</p>
      ${a.due_at?`<p class="muted">Due ${dateTime(a.due_at)}</p>`:''}
      ${items.map(i=>i.kind==='file'?button('Open attachment','open-file',false,i.id):
        i.kind==='link'&&safeLink(i.body)?`<p><a href="${escape(safeLink(i.body))}" target="_blank" rel="noopener noreferrer">${escape(i.title)}</a></p>`:
        `<p class="body-text"><strong>${escape(i.title)}</strong><br>${escape(i.body)}</p>`).join('')}
      ${receipt?.status==='completed'?'':`<div class="actions">${!receipt?button('Mark read','work-read',false,a.id):''}
        ${button('Complete assignment','work-complete',true,a.id)}</div>`}</article>`;
  }).join('')||'<section class="card"><p class="muted">No assignments yet.</p></section>'}</div>
  <section class="card" style="margin-top:14px"><h2>Report files</h2>
    <p class="muted">Attach a file for your admin. Daily Work Reports are submitted at clock-out.</p>
    ${button('Upload report file','upload-file')}
    ${table(['File','Uploaded'],data.submissions.map(s=>[escape(s.file_name),dateTime(s.created_at)]))}</section>`;
}
function settings(){
  const e=data.employee;
  return `<div class="tiles"><section class="card"><h2>Employee profile</h2><div class="fields">
    <label>Display name<input readonly value="${escape(e.display_name||e.name)}"></label>
    <label>Employee ID<input readonly value="${escape(e.employee_code)}"></label>
    <label>Company<input readonly value="${escape(data.settings[0]?.company_name||'Montme')}"></label></div>
    ${button('Edit display name','edit-name',true)}</section>
    <section class="card"><h2>Company connection</h2><p>${escape(e.email)}</p>
    <p class="muted">Attendance, work, and company notifications sync with your mobile app.</p>
    <h2>Browser notifications</h2><p class="muted">${pushReady?'Delivery is enabled on this browser.':'Allow notifications to receive Montme alerts on this browser.'}</p>
    ${button(pushReady?'Disable notifications':'Enable notifications',pushReady?'disable-push':'enable-push')}</section></div>`;
}
function inbox(){
  return `<div class="stack">${notifications().map(n=>`<article class="card ${read(n.id)?'':'unread'}">
    <p class="muted">${dateTime(n.available_at)}</p><h2>${escape(n.title)}</h2><p class="body-text">${escape(n.body)}</p>
    ${button(read(n.id)?'Mark unread':'Mark read','read-notification',false,n.id)}</article>`).join('')||
    '<section class="card"><p class="muted">You have no notifications yet.</p></section>'}</div>`;
}
function render(){
  if(!data)return;
  const unread=notifications().filter(n=>!read(n.id)).length;
  const company=data.settings[0]?.company_name||'Montme';
  const titles={Today:'Your workday',Leads:'Your leads',Calls:'Business calls',Reports:'Reports',Work:'Assigned work',Settings:'Settings',Notifications:'Notifications'};
  const content={Today:today,Leads:leads,Calls:callList,Reports:reports,Work:work,Settings:settings,Notifications:inbox};
  const markup=`<div class="shell"><aside class="rail">${brand}<nav aria-label="Workspace">
    ${Object.entries(pages).map(([name,path])=>`<button data-view="${name}" ${view===name?'aria-current="page"':''}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>${name}</button>`).join('')}
    </nav><span class="rail-footer">Connected to ${escape(company)}</span></aside>
    <div class="workspace"><header class="top"><strong>${escape(data.employee.display_name||data.employee.name)}</strong>
    <div class="actions"><button class="btn" data-view="Notifications">Notifications${unread?` (${unread})`:''}</button>
    ${button('Sign out','sign-out')}</div></header>
    <main class="main"><header><div><h1>${titles[view]}</h1>
    ${view==='Today'?`<p class="muted">${new Intl.DateTimeFormat('en-IN',{timeZone:tz,dateStyle:'full'}).format(new Date())}</p>`:''}</div>
    <div class="actions"><small id="employee-sync" class="muted"></small>${button('Refresh','refresh')}</div></header>${content[view]()}</main></div></div>`;
  if(markup!==lastMarkup){
    root.innerHTML=markup;
    lastMarkup=markup;
  }
  root.querySelector('#employee-sync').textContent=lastSync?'Last synced '+dateTime(lastSync):'';
}
async function refresh(){
  await load();
  if(!dialog.open&&!document.activeElement?.closest('[data-filter]'))render();
}
async function start(){
  await load();
  pushReady=webPushEnabled(repo);
  render();
  if(pushReady)enableWebPush(repo,data.settings[0]?.firebase_config,
    ()=>refresh().catch(()=>{})).catch(()=>{pushReady=false;render();});
  clearInterval(timer);
  timer=setInterval(()=>{
    if(document.hidden||busy)return;
    refresh().catch(error=>{
      if(!repo.session)loginScreen(error.message);
      else announce('Connection interrupted. Displaying the last synced records.');
    });
  },5000);
}
window.addEventListener('hashchange',()=>{
  if(location.hash==='#notifications'&&data){view='Notifications';render();}
});
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&data&&!busy)refresh().catch(error=>announce(error.message));});

function openDialog(title,body,submitLabel,submit){
  dialog.innerHTML=`<form><h2>${title}</h2>${body}<p class="error" role="alert"></p>
    <div class="actions"><button type="button" class="btn" data-action="cancel">${submit?'Cancel':'Close'}</button>
    ${submit?`<button class="btn primary" type="submit">${submitLabel}</button>`:''}</div></form>`;
  const form=dialog.querySelector('form');
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    if(busy||!submit)return;
    const values=new FormData(form);
    busy=true;
    const controls=[...form.querySelectorAll('button,input,select,textarea')];
    controls.forEach(control=>control.disabled=true);
    try{
      await submit(values);
      dialog.close();
      await refresh();
    }catch(error){
      if(dialog.open)form.querySelector('.error').textContent=error.message;
      else announce(error.message);
    }finally{
      busy=false;
      controls.forEach(control=>control.disabled=false);
    }
  });
  dialog.showModal();
}
dialog.addEventListener('cancel',event=>{if(busy)event.preventDefault();});

async function upload(file){
  if(!file?.size||file.size>20*1024*1024)throw Error('Choose a non-empty file up to 20 MB.');
  const path=`${data.employee.id}/${crypto.randomUUID()}/${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
  const bucket='/storage/v1/object/montme-submissions';
  await repo.request(bucket+'/'+path,{method:'POST',body:file,raw:true,
    headers:{'Content-Type':'application/octet-stream','x-upsert':'false'}});
  try{
    await repo.request('/rest/v1/work_submissions',{method:'POST',body:{
      employee_id:data.employee.id,file_path:path,file_name:file.name,
      mime_type:'application/octet-stream',size_bytes:file.size}});
  }catch(error){
    await repo.request(bucket,{method:'DELETE',body:{prefixes:[path]}}).catch(()=>{});
    throw error;
  }
}
function leadFields(contact){
  return `<label>Status<select name="status">${options(leadStatuses,contact?.status||'New')}</select></label>
    <label>Notes<textarea name="notes" maxlength="10000">${escape(contact?.notes)}</textarea></label>
    <label>Follow-up (IST)<input type="datetime-local" name="follow" value="${localTime(contact?.follow_up_at)}"></label>`;
}
function updateContact(contact,status,notes,follow){
  return rpc('update_my_contact',{contact_id_input:contact.id,status_input:status,notes_input:notes,follow_up_input:follow});
}
function contactForm(contact){
  const editDetails=!contact||leadWritesAvailable&&contact.created_by_employee===data.employee.id;
  const id=contact?.id||crypto.randomUUID();
  openDialog(contact?'Edit lead':'Add lead',`<div class="fields">${editDetails?`
    <label>Name<input name="name" maxlength="120" required value="${escape(contact?.name)}"></label>
    <label>Phone<input name="phone" type="tel" maxlength="40" required value="${escape(contact?.phone)}"></label>
    <label>Institution<input name="institution" maxlength="200" value="${escape(contact?.institution||contact?.company)}"></label>`:''}
    ${leadFields(contact)}</div>`,'Save lead',async form=>{
    const status=form.get('status'),notes=form.get('notes'),follow=isoTime(form.get('follow'));
    if(!editDetails)return updateContact(contact,status,notes,follow);
    const saved=await rpc('save_my_leads',{leads_input:[{id,edit:Boolean(contact),
      name:form.get('name'),phone:form.get('phone'),institution:form.get('institution'),
      status,notes,follow_up_at:follow}]});
    announce(saved?'Lead saved.':'A matching lead is already in your workspace.');
  });
}
function bulkLeadForm(){
  const ids=new Map();
  openDialog('Bulk add leads',`<p>Paste up to 200 leads, one per line, as Name | Phone | Institution. Duplicate phone numbers are skipped.</p>
    <div class="fields"><label>Leads<textarea name="lines" required placeholder="Asha Rao | +919876543210 | Example Institute"></textarea></label></div>`,
    'Add leads',async form=>{
      const lines=form.get('lines').split(/\r?\n/).filter(line=>line.trim());
      if(!lines.length||lines.length>200)throw Error('Enter 1 to 200 leads at a time.');
      const leads=lines.map((line,i)=>{
        const fields=line.split('|').map(value=>value.trim());
        const [name,phone,institution='']=fields;
        if(fields.length<2||fields.length>3||!name||name.length>120||institution.length>200||phone.length>40||
          !/^\+?[0-9 ()-]+$/.test(phone)||!/^\d{7,15}$/.test(phone.replace(/\D/g,'')))throw Error(`Check lead row ${i+1}.`);
        if(!ids.has(line))ids.set(line,crypto.randomUUID());
        return {id:ids.get(line),name,phone,institution};
      });
      const saved=await rpc('save_my_leads',{leads_input:leads});
      announce(`${saved} added. ${leads.length-saved} duplicates skipped.`);
    });
}
function callReviewFields(call){
  const lead=data.contacts.find(c=>c.id===call?.contact_id);
  return `<label>Outcome<select name="outcome">${options(outcomes,call?.outcome||'Not reviewed')}</select></label>
    <label>Notes<textarea name="notes" maxlength="10000">${escape(call?.notes)}</textarea></label>
    ${leadWritesAvailable?`<label>Next follow-up (IST)<input name="follow" type="datetime-local" value="${localTime(lead?.follow_up_at)}"></label>`:''}`;
}
function reviewCall(id,form){
  return rpc('review_my_call',{call_input:id,outcome_input:form.get('outcome'),notes_input:form.get('notes'),
    follow_up_input:isoTime(form.get('follow'))});
}
function callForm(call){
  if(call){
    openDialog('Edit call outcome',`<div class="fields">${callReviewFields(call)}</div>`,'Save outcome',
      form=>reviewCall(call.device_call_id,form));
    return;
  }
  if(!data.contacts.length)throw Error('Add a lead or ask your admin to assign one before logging a call.');
  const id=crypto.randomUUID();
  openDialog('Log a business call',`<div class="fields"><label>Lead<select name="lead" required>
    ${data.contacts.map(c=>`<option value="${escape(c.id)}">${escape(c.name)}</option>`).join('')}</select></label>
    <label>Call time (IST)<input type="datetime-local" name="at" required value="${localTime(new Date())}"></label>
    <label>Direction<select name="direction"><option>Outgoing</option><option>Incoming</option><option>Missed</option><option>Rejected</option></select></label>
    <label>Duration in seconds<input name="duration" type="number" min="0" max="86400" value="0" required></label>
    ${callReviewFields()}</div>`,'Save call',async form=>{
    const contact=data.contacts.find(c=>c.id===form.get('lead'));
    const at=isoTime(form.get('at')),direction=form.get('direction'),seconds=Number(form.get('duration'));
    if(Date.parse(at)>Date.now())throw Error('A call cannot be logged in the future.');
    if(['Missed','Rejected'].includes(direction)&&seconds)throw Error('Missed and rejected calls must have zero talk time.');
    await repo.request('/rest/v1/call_records?on_conflict=employee_id,device_call_id',{method:'POST',
      headers:{Prefer:'resolution=ignore-duplicates'},body:{
      employee_id:data.employee.id,contact_id:contact.id,device_call_id:id,
      phone:contact.phone,lead_name:contact.name,started_at:at,source:'Manual',
      direction,duration_seconds:seconds,outcome:form.get('outcome'),notes:form.get('notes')}});
    if(leadWritesAvailable)await reviewCall(id,form);
  });
}
function downloadWorkbook(name,rows){
  const url=URL.createObjectURL(new Blob([workbook(rows)],{
    type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
  const link=document.createElement('a');
  link.href=url;link.download=name;link.click();
  setTimeout(()=>URL.revokeObjectURL(url),5000);
}
function callRows(records){
  return [['Call time (IST)','Lead','Phone','Direction','Duration seconds','Outcome','Notes'],
    ...records.map(c=>[dateTime(c.started_at),c.lead_name||data.contacts.find(l=>l.id===c.contact_id)?.name,
      c.phone,c.direction,c.duration_seconds,c.outcome,c.notes])];
}
document.addEventListener('submit',event=>{
  const form=event.target;
  if(!form.dataset.filter)return;
  event.preventDefault();
  const values=new FormData(form);
  if(form.dataset.filter==='leads'){
    leadSearch=values.get('search').trim();leadStatus=values.get('status');
  }else callDay=values.get('day');
  render();
});
async function handle(action,id){
  const shift=current();
  switch(action){
    case 'refresh': await refresh();break;
    case 'sign-out':
      await disableWebPush(repo).catch(()=>{});
      pushReady=false;
      await repo.request('/auth/v1/logout?scope=local',{method:'POST'}).catch(()=>{});
      repo.session=null;sessionStorage.removeItem(repo.authStorageKey);
      loginScreen();break;
    case 'clock-in': await rpc('clock_in');announce('Clocked in.');break;
    case 'clock-out':
      if(!shift)return;
      openDialog('Daily Work Report','<p>Submit this shift’s work time, breaks and synced business calls to your company to clock out. If you logged calls on Android, sync the phone before submitting here.</p>',
        'Submit report and clock out',async()=>{await rpc('submit_daily_report',{shift_input:shift.device_shift_id});announce('Daily Work Report submitted. You’re clocked out.');});
      break;
    case 'early':
      if(!shift)return;
      openDialog('Request early clock-out','<div class="fields"><label>Reason<textarea name="reason" maxlength="1000" required></textarea></label></div>',
        'Send request',form=>rpc('request_early_exit',{shift_input:shift.device_shift_id,reason_input:form.get('reason').trim()}));
      break;
    case 'break': {
      if(!shift)return;
      const change=kind=>rpc('toggle_shift_break',{shift_input:shift.device_shift_id,expected_input:shift.breaks,kind_input:kind});
      const pause=shift.breaks.at(-1);
      if(pause&&!pause.end){await change(null);break;}
      openDialog('Start break','<div class="fields"><label>Break type<select name="kind"><option value="">Scheduled break</option><option value="lunch">Lunch</option><option value="evening">Evening</option><option value="extra">Extra break</option></select></label></div>','Start break',form=>change(form.get('kind')||null));
      break;
    }
    case 'new-lead': contactForm();break;
    case 'bulk-leads': bulkLeadForm();break;
    case 'complete-follow-up': {
      const lead=data.contacts.find(c=>c.id===id);
      openDialog('Complete follow-up','<p>Clear the scheduled follow-up for this lead?</p>','Complete',
        ()=>updateContact(lead,lead.status,lead.notes,null));
      break;
    }
    case 'clear-call-filter': callDay='';render();break;
    case 'review-call': callForm(calls().find(c=>c.id===id));break;
    case 'export-calls': downloadWorkbook('montme-calls.xlsx',callRows(visibleCalls()));break;
    case 'export-all-calls': downloadWorkbook('montme-calls.xlsx',callRows(calls()));break;
    case 'export-report':{
      const report=data.reports.find(r=>r.id===id);
      downloadWorkbook(`daily-work-report-${report.work_day}.xlsx`,[
        ['Work date (IST)','Clock in','Clock out'],[report.work_day,dateTime(report.started_at),dateTime(report.ended_at)],
        [],['Break','Start','End'],...report.breaks.map(b=>[b.kind,dateTime(b.start),dateTime(b.end)]),
        [],...callRows(report.calls)]);
      break;
    }
    case 'edit-lead': contactForm(data.contacts.find(c=>c.id===id));break;
    case 'log-call': callForm();break;
    case 'edit-name':
      openDialog('Edit display name',`<div class="fields"><label>Display name<input name="name" maxlength="120" required value="${escape(data.employee.display_name||data.employee.name)}"></label></div>`,
        'Save name',form=>rpc('set_my_display_name',{name_input:form.get('name')}));
      break;
    case 'report':{
      const report=data.reports.find(r=>r.id===id);
      openDialog('Daily Work Report',`<p>${dateTime(report.started_at)} to ${dateTime(report.ended_at)} &middot; ${report.breaks.length} breaks</p>
        ${table(['Lead','Direction','Duration','Outcome'],report.calls.map(c=>[
          escape(c.lead_name),escape(c.direction),duration(c.duration_seconds),escape(c.outcome)]))}`);
      break;
    }
    case 'read-notification': await repo.markNotification(id,!read(id));break;
    case 'work-read':
    case 'work-complete': {
      await rpc('acknowledge_assignment',{assignment_id_input:id,
        status_input:action==='work-complete'?'completed':'read'});
      break;
    }
    case 'open-file': {
      const url=await repo.fileUrl(data.content.find(c=>c.id===id));
      openDialog('Assignment attachment',`<p><a href="${escape(url)}" target="_blank" rel="noopener noreferrer">Open protected file</a></p>`);break;
    }
    case 'upload-file':
      openDialog('Upload report file','<div class="fields"><label>Report file<input name="file" type="file" accept=".xlsx,.pdf,.txt,.csv,.json" required></label></div>',
        'Upload',form=>upload(form.get('file')));
      break;
    case 'enable-push':
      await enableWebPush(repo,data.settings[0]?.firebase_config,()=>refresh().catch(()=>{}));
      pushReady=true;announce('Browser notifications enabled.');break;
    case 'disable-push':
      await disableWebPush(repo);pushReady=false;announce('Browser notifications disabled.');break;
  }
}
document.addEventListener('click',async event=>{
  const control=event.target.closest('[data-view],[data-action]');
  if(!control||busy)return;
  if(control.dataset.view){view=control.dataset.view;render();return;}
  if(control.dataset.action==='cancel'){dialog.close();return;}
  if(!data)return;
  busy=true;control.disabled=true;
  try{
    await handle(control.dataset.action,control.dataset.id);
    if(data&&!dialog.open)await refresh();
  }catch(error){announce(error.message);}
  finally{busy=false;control.disabled=false;}
});

if(repo.session)start().catch(async error=>{
  if(repo.session)await repo.logout();
  loginScreen(error.message);
});
else loginScreen();
