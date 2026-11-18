import test from 'node:test';
import assert from 'node:assert/strict';
const memory=()=>{const m=new Map();return {getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}};
globalThis.window={MONTME_CONFIG:{}};globalThis.localStorage=memory();globalThis.sessionStorage=memory();
const {assignmentStatus,occurrences,exportCsv,Repository,saveConfig}=await import('../dist/api.js');
test('Scheduled assignments remain hidden until delivery; completion requires every recipient',()=>{
 const a={id:'a',state:'published',recipient_ids:['one','two'],release_at:'2026-11-18T03:30:00Z',due_at:'2026-11-18T11:30:00Z'};
 assert.equal(assignmentStatus(a,[],new Date('2026-11-18T03:29:59Z')),'Scheduled');
 assert.equal(assignmentStatus(a,[],new Date(a.release_at)),'Published');
 assert.equal(assignmentStatus(a,[],new Date('2026-11-19')),'Overdue');
 assert.equal(assignmentStatus(a,[{assignment_id:'a',employee_id:'one',status:'completed'}],new Date('2026-11-19')),'Overdue');
 assert.equal(assignmentStatus(a,['one','two'].map(employee_id=>({assignment_id:'a',employee_id,status:'completed'})),new Date('2026-11-19')),'Completed');
 assert.equal(assignmentStatus({...a,state:'draft'},[],new Date('2026-11-19')),'Draft');
 assert.equal(assignmentStatus({...a,state:'cancelled'},[],new Date('2026-11-19')),'Cancelled');
});
test('Daily repeats include the end date and keep Indian time',()=>{
 const dates=occurrences('2026-11-18T09:00:00+05:30','2026-11-20T23:59:59+05:30','daily');
 assert.deepEqual(dates.map(d=>d.toISOString()),['2026-11-18T03:30:00.000Z','2026-11-19T03:30:00.000Z','2026-11-20T03:30:00.000Z']);
});
test('Monthly repeats handle February and midnight IST',()=>{
 const dates=occurrences('2026-01-31T00:30:00+05:30','2026-03-31T23:59:59+05:30','monthly');
 assert.deepEqual(dates.map(d=>d.toISOString()),['2026-01-30T19:00:00.000Z','2026-02-27T19:00:00.000Z','2026-03-30T19:00:00.000Z']);
 assert.throws(()=>occurrences('2026-11-18','2028-01-01','daily'),/one year/);
});
test('CSV cells do not execute as spreadsheet formulas',()=>{assert.match(exportCsv([['=SUM(A1)','A, B','00123']]),/"'=SUM/)});
test('Local saves and schedule edits persist without contacting Supabase',async()=>{
 const r=new Repository(true);await r.load();const e=await r.save('employees',{name:'Test',email:'test@example.com',active:true});
 await r.saveAssignments([{title:'Task',recipient_ids:[e.id],content_ids:['used'],state:'published',release_at:'2026-11-18T03:30:00Z',series_id:'s'}]);
 const id=r.data.assignments[0].id;await r.save('assignments',{id,title:'Updated'});
 const reload=new Repository(true);await reload.load();assert.equal(reload.data.assignments[0].title,'Updated');assert.equal(reload.data.assignments[0].recipient_ids[0],e.id);
 await assert.rejects(r.deleteContent({id:'used'}),/used in an assignment/);
});
test('Connection settings reject service-role JWTs',()=>{
 const token='eyJ.'+btoa(JSON.stringify({role:'service_role'}))+'.test';
 assert.throws(()=>saveConfig({url:'https://project.supabase.co',key:token,adminEmail:'a@example.com'}),/anon key/);
});
