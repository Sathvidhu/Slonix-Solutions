import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
const admin='00000000-0000-4000-8000-000000000001',employee='00000000-0000-4000-8000-000000000002',outsider='00000000-0000-4000-8000-000000000003';
let db;
async function asUser(uid,sql){await db.exec(`set role authenticated;select set_config('request.jwt.claim.sub','${uid}',false);`);try{return await db.exec(sql)}finally{await db.exec('reset role;')}}
test('Migration preserves history and enforces roles, notification receipts and break windows',async()=>{
 db=new PGlite();await db.waitReady;
 try{
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create table auth.users(id uuid primary key,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth,storage to authenticated,anon;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant all on storage.objects to authenticated;insert into auth.users(id,email)values('${admin}','slonixbim.team@gmail.com'),('${employee}','employee@example.com'),('${outsider}','outsider@example.com');`);
 const initial=(await readFile(new URL('../supabase/schema.sql',import.meta.url),'utf8')).replace('create extension if not exists pgcrypto;','');await db.exec(initial);
 await db.exec(`insert into public.employees(id,name,email,employee_code,auth_id)values('${employee}','Employee','employee@example.com','EMP-01','${employee}');insert into public.contacts(name,company,phone)values('Existing contact','Existing institute','9876543210');insert into public.shift_records(employee_id,device_shift_id,started_at,ended_at,breaks)values('${employee}','old','2026-11-17T03:30:00Z','2026-11-17T12:30:00Z','[{"start":"2026-11-17T08:00:00Z","end":"2026-11-17T09:00:00Z"}]');`);
 await db.exec(await readFile(new URL('../supabase/migrations/20261118_004_people_notifications.sql',import.meta.url),'utf8'));
 const cron=(await readFile(new URL('../supabase/migrations/20261118_005_notification_cron.sql',import.meta.url),'utf8')).split('create extension if not exists pg_cron')[0];await db.exec(cron);
 await db.exec(await readFile(new URL('../supabase/migrations/20261118_006_notification_operations.sql',import.meta.url),'utf8'));
 assert.equal((await db.query('select institution from contacts')).rows[0].institution,'Existing institute');
 assert.equal((await db.query('select count(*)::int as n from break_records')).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int as n from notifications')).rows[0].n,0);
 await asUser(admin,`select public.create_assignment_batch('[{"title":"High priority","message":"Do work","recipient_ids":["${employee}"],"priority":"High","release_at":"2020-01-01T00:00:00Z","state":"published"}]');`);
 assert.equal((await db.query("select count(*)::int as n from notification_deliveries where channel='email'")).rows[0].n,1);
 const n=(await db.query('select id from notifications')).rows[0].id;
 assert.equal((await asUser(outsider,'select * from public.notifications;'))[0].rows.length,0);
 assert.equal((await asUser(employee,'select * from public.notifications;'))[0].rows.length,1);
 await assert.rejects(asUser(outsider,`select public.set_notification_read('${n}',true);`),/not available/);
 await asUser(employee,`select public.set_notification_read('${n}',true);select public.set_notification_read('${n}',false);`);
 const receipt=(await db.query('select read_at,first_read_at from notification_receipts')).rows[0];assert.equal(receipt.read_at,null);assert.ok(receipt.first_read_at);
 await assert.rejects(asUser(employee,`insert into public.workspace_roles(name,permissions)values('Bad',array['roles.manage']);`),/row-level security/);
 await assert.rejects(asUser(employee,`update public.employees set role_id=(select id from workspace_roles where name='Manager') where id='${employee}';`),/permission denied/);
 const deadline=(await db.query("select public.break_deadline('2026-11-18T08:10:00Z','lunch')::text as lunch,public.break_deadline('2026-11-18T11:40:00Z','evening')::text as evening,public.break_deadline('2026-11-18T06:00:00Z','extra')::text as extra")).rows[0];
 assert.match(deadline.lunch,/09:00:00/);assert.match(deadline.evening,/12:00:00/);assert.match(deadline.extra,/06:10:00/);
 await asUser(employee,`insert into public.shift_records(employee_id,device_shift_id,started_at,breaks)values('${employee}','new','2026-11-18T03:30:00Z','[{"start":"2026-11-18T08:10:00Z","kind":"lunch","end":null}]');`);
 const count=(await db.query('select count(*)::int as n from notifications')).rows[0].n;
 await asUser(employee,`update shift_records set breaks=breaks where device_shift_id='new';`);
 assert.equal((await db.query('select count(*)::int as n from notifications')).rows[0].n,count);
 await asUser(employee,`update shift_records set breaks='[{"start":"2026-11-18T08:10:00Z","kind":"lunch","end":"2026-11-18T08:50:00Z"}]' where device_shift_id='new';`);
 assert.equal((await db.query("select count(*)::int as n from notifications where kind='break_reminder' and cancelled_at is null")).rows[0].n,0);
 }finally{await db.close();}
});
