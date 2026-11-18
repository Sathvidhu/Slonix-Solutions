-- Upgrade the existing Montme schema. Run in Supabase SQL Editor as postgres.
-- Preserves current employees, contacts, assignments, calls, shifts and breaks.
begin;
create table if not exists public.schema_migrations(version text primary key,installed_at timestamptz not null default now());
create table if not exists public.workspace_roles(id uuid primary key default gen_random_uuid(),name text not null unique,permissions text[] not null default '{}',created_at timestamptz not null default now(),check(permissions <@ array['employees.manage','roles.manage','contacts.manage','assignments.manage','activity.view','notifications.manage','settings.manage']::text[]));
insert into public.workspace_roles(name,permissions) values('Employee','{}'),('Manager',array['contacts.manage','assignments.manage','activity.view','notifications.manage']) on conflict(name) do nothing;
alter table public.employees add column if not exists role_id uuid references public.workspace_roles(id);
update public.employees set role_id=(select id from public.workspace_roles where name='Employee') where role_id is null;
alter table public.employees add column if not exists login_key text generated always as(lower(employee_code)) stored;
create unique index if not exists employee_code_case_insensitive on public.employees(lower(employee_code));
create function public.has_permission(permission_name text) returns boolean language sql stable security definer set search_path='' as $$select public.is_admin() or exists(select 1 from public.employees e join public.workspace_roles r on r.id=e.role_id where e.auth_id=auth.uid() and e.active and permission_name=any(r.permissions))$$;
revoke all on function public.has_permission(text) from public;grant execute on function public.has_permission(text) to authenticated;
-- Keep the legacy company field for old app compatibility; institution is canonical.
alter table public.contacts add column if not exists institution text;
update public.contacts set institution=company where institution is null;
alter table public.contacts alter column institution set default '';
alter table public.contacts alter column institution set not null;
create function public.sync_institution() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='INSERT' then if new.institution='' and new.company<>'' then new.institution:=new.company;else new.company:=new.institution;end if;
 elsif new.institution is distinct from old.institution then new.company:=new.institution;
 elsif new.company is distinct from old.company then new.institution:=new.company;end if;return new;end$$;
create trigger montme_institution before insert or update on public.contacts for each row execute function public.sync_institution();
create table public.workspace_settings(id boolean primary key default true check(id),lunch_start time not null default '13:30',lunch_end time not null default '14:30',evening_start time not null default '17:00',evening_end time not null default '17:30',extra_break_minutes integer not null default 10 check(extra_break_minutes between 1 and 60),check(lunch_end>lunch_start),check(evening_end>evening_start),firebase_config jsonb not null default '{}',email_high_priority boolean not null default true,created_at timestamptz not null default now());
insert into public.workspace_settings(id) values(true);
create table public.activity_events(id uuid primary key default gen_random_uuid(),employee_id uuid references public.employees(id),kind text not null,title text not null,occurred_at timestamptz not null default now(),detail jsonb not null default '{}',event_key text unique,created_at timestamptz not null default now());
create index activity_employee_time on public.activity_events(employee_id,occurred_at desc);
create table public.break_records(id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id),shift_id uuid not null references public.shift_records(id) on delete cascade,break_index integer not null check(break_index>=0),started_at timestamptz not null,ended_at timestamptz,kind text not null default 'extra' check(kind in('lunch','evening','extra')),deadline_at timestamptz,created_at timestamptz not null default now(),unique(shift_id,break_index),check(ended_at is null or ended_at>=started_at));
-- Backfill historical break intervals without generating new historical alerts.
insert into public.break_records(employee_id,shift_id,break_index,started_at,ended_at)
select s.employee_id,s.id,(b.ordinality-1)::integer,(b.value->>'start')::timestamptz,nullif(b.value->>'end','')::timestamptz from public.shift_records s cross join lateral jsonb_array_elements(s.breaks) with ordinality as b(value,ordinality) on conflict(shift_id,break_index) do nothing;
create function public.break_kind(at_input timestamptz) returns text language sql stable set search_path='' as $$select case when (at_input at time zone 'Asia/Kolkata')::time>=lunch_start and (at_input at time zone 'Asia/Kolkata')::time<lunch_end then 'lunch' when (at_input at time zone 'Asia/Kolkata')::time>=evening_start and (at_input at time zone 'Asia/Kolkata')::time<evening_end then 'evening' else 'extra' end from public.workspace_settings where id$$;
create function public.break_deadline(start_input timestamptz,kind_input text) returns timestamptz language sql stable set search_path='' as $$select case when kind_input='lunch' then (((start_input at time zone 'Asia/Kolkata')::date+lunch_end) at time zone 'Asia/Kolkata') when kind_input='evening' then (((start_input at time zone 'Asia/Kolkata')::date+evening_end) at time zone 'Asia/Kolkata') else start_input+make_interval(mins=>extra_break_minutes) end from public.workspace_settings where id$$;
update public.break_records set kind=public.break_kind(started_at),deadline_at=public.break_deadline(started_at,public.break_kind(started_at));
create table public.notifications(id uuid primary key default gen_random_uuid(),employee_id uuid references public.employees(id),audience text not null check(audience in ('employee','admin')),title text not null,body text not null default '',kind text not null,priority text not null default 'Normal' check(priority in ('Normal','High','Urgent')),assignment_id uuid references public.assignments(id) on delete cascade,available_at timestamptz not null default now(),cancelled_at timestamptz,event_key text not null unique,created_at timestamptz not null default now(),check((audience='employee' and employee_id is not null) or (audience='admin' and employee_id is null)));
create index notification_recipient_time on public.notifications(employee_id,available_at desc);
create table public.notification_receipts(id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.notifications(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,read_at timestamptz,first_read_at timestamptz,created_at timestamptz not null default now(),unique(notification_id,user_id));
create table public.notification_deliveries(id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.notifications(id) on delete cascade,channel text not null check(channel in ('email','push')),status text not null default 'pending' check(status in ('pending','processing','retry','sent','blocked','failed','skipped','cancelled')),attempts integer not null default 0,available_at timestamptz not null default now(),locked_at timestamptz,sent_at timestamptz,last_error text,provider_id text,created_at timestamptz not null default now(),unique(notification_id,channel));
create table public.push_devices(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,token text not null unique,platform text not null default 'android',updated_at timestamptz not null default now(),created_at timestamptz not null default now());
create table public.login_rate_limits(bucket text primary key,window_start timestamptz not null,attempts integer not null);
create function public.allow_employee_login(bucket_input text) returns boolean language plpgsql security definer set search_path='' as $$declare count_input integer;begin
 insert into public.login_rate_limits(bucket,window_start,attempts) values(bucket_input,now(),1) on conflict(bucket) do update set attempts=case when public.login_rate_limits.window_start<now()-interval '15 minutes' then 1 else public.login_rate_limits.attempts+1 end,window_start=case when public.login_rate_limits.window_start<now()-interval '15 minutes' then now() else public.login_rate_limits.window_start end returning attempts into count_input;return count_input<=10;end$$;
revoke all on function public.allow_employee_login(text) from public,anon,authenticated;grant execute on function public.allow_employee_login(text) to service_role;
create function public.queue_notification(employee_input uuid,audience_input text,title_input text,body_input text,kind_input text,key_input text,priority_input text default 'Normal',available_input timestamptz default now(),assignment_input uuid default null) returns uuid language plpgsql security definer set search_path='' as $$declare nid uuid;begin
 insert into public.notifications(employee_id,audience,title,body,kind,event_key,priority,available_at,assignment_id) values(employee_input,audience_input,title_input,body_input,kind_input,key_input,priority_input,available_input,assignment_input) on conflict(event_key) do nothing returning id into nid;
 if nid is not null then
 insert into public.notification_deliveries(notification_id,channel,available_at) values(nid,'push',available_input);
 if priority_input in ('High','Urgent') and (select email_high_priority from public.workspace_settings where id) then insert into public.notification_deliveries(notification_id,channel,available_at) values(nid,'email',available_input);end if;
 end if;return nid;end$$;
revoke all on function public.queue_notification(uuid,text,text,text,text,text,text,timestamptz,uuid) from public,anon,authenticated;
create function public.assignment_notifications() returns trigger language plpgsql security definer set search_path='' as $$declare eid uuid;begin
 if new.state<>'published' then update public.notifications set cancelled_at=now() where assignment_id=new.id and cancelled_at is null;update public.notification_deliveries set status='cancelled' where notification_id in(select id from public.notifications where assignment_id=new.id) and status in('pending','retry','blocked','processing');return new;end if;
 update public.notifications set cancelled_at=now() where assignment_id=new.id and not(employee_id=any(new.recipient_ids));
 foreach eid in array new.recipient_ids loop
 perform public.queue_notification(eid,'employee','New assignment: '||new.title,new.message,'assignment','assignment:'||new.id||':'||eid,new.priority,new.release_at,new.id);
 update public.notifications set title='New assignment: '||new.title,body=new.message,priority=new.priority,available_at=new.release_at,cancelled_at=null where assignment_id=new.id and employee_id=eid;
 update public.notification_deliveries d set available_at=new.release_at where d.notification_id in(select id from public.notifications where assignment_id=new.id and employee_id=eid) and d.status in('pending','retry','blocked');
 if new.priority in('High','Urgent') and (select email_high_priority from public.workspace_settings where id) then insert into public.notification_deliveries(notification_id,channel,available_at) select id,'email',new.release_at from public.notifications where assignment_id=new.id and employee_id=eid on conflict(notification_id,channel) do nothing;end if;
 end loop;return new;end$$;
create trigger montme_assignment_notifications after insert or update of title,message,recipient_ids,priority,state,release_at on public.assignments for each row execute function public.assignment_notifications();
create function public.attendance_events() returns trigger language plpgsql security definer set search_path='' as $$declare item jsonb;idx integer;label text;kind_input text;deadline_input timestamptz;rec public.break_records;begin
 select name into label from public.employees where id=new.employee_id;
 if tg_op='INSERT' then
 insert into public.activity_events(employee_id,kind,title,occurred_at,event_key) values(new.employee_id,'clock_in',label||' clocked in',new.started_at,'clock-in:'||new.id) on conflict(event_key) do nothing;
 perform public.queue_notification(null,'admin',label||' clocked in','Shift started.','attendance','clock-in:'||new.id);
 end if;
 if new.ended_at is not null and (tg_op='INSERT' or old.ended_at is null) then
 insert into public.activity_events(employee_id,kind,title,occurred_at,event_key) values(new.employee_id,'clock_out',label||' clocked out',new.ended_at,'clock-out:'||new.id) on conflict(event_key) do nothing;
 perform public.queue_notification(null,'admin',label||' clocked out','Shift ended.','attendance','clock-out:'||new.id);
 end if;
 if jsonb_typeof(new.breaks)<>'array' then raise exception 'Breaks must be an array.';end if;
 idx:=0;
 for item in select value from jsonb_array_elements(new.breaks) loop
 if (item->>'start')::timestamptz<new.started_at or (new.ended_at is not null and (item->>'end' is null or (item->>'end')::timestamptz>new.ended_at)) then raise exception 'Break interval lies outside shift.';end if;
 select * into rec from public.break_records where shift_id=new.id and break_index=idx;
 if rec.id is null then
 kind_input:=coalesce(item->>'kind',public.break_kind((item->>'start')::timestamptz));
 deadline_input:=public.break_deadline((item->>'start')::timestamptz,kind_input);
 insert into public.break_records(employee_id,shift_id,break_index,started_at,ended_at,kind,deadline_at) values(new.employee_id,new.id,idx,(item->>'start')::timestamptz,(item->>'end')::timestamptz,kind_input,deadline_input);
 insert into public.activity_events(employee_id,kind,title,occurred_at,event_key) values(new.employee_id,'break_start',label||' started a break',(item->>'start')::timestamptz,'break-start:'||new.id||':'||idx) on conflict(event_key) do nothing;
 perform public.queue_notification(null,'admin',label||' started a break','Break start recorded.','break','break-start:'||new.id||':'||idx);
 if item->>'end' is null or (item->>'end')::timestamptz>deadline_input then
 perform public.queue_notification(new.employee_id,'employee',initcap(kind_input)||' break exceeded','Your break limit has been reached. Return to Montme to resume work.','break_reminder','break-reminder:'||new.id||':'||idx,'High',deadline_input);
 perform public.queue_notification(null,'admin',label||' - '||kind_input||' break exceeded','The break has exceeded its allowed time.','break_reminder','admin-break-reminder:'||new.id||':'||idx,'High',deadline_input);
 end if;
 if kind_input='extra' and (select count(*) from public.break_records where employee_id=new.employee_id and kind='extra' and (started_at at time zone 'Asia/Kolkata')::date=((item->>'start')::timestamptz at time zone 'Asia/Kolkata')::date)>1 then
 perform public.queue_notification(null,'admin',label||' took an additional extra break','Only one extra break is allowed per day. This interval has still been recorded.','break_policy','extra-break-policy:'||new.id||':'||idx,'High');
 perform public.queue_notification(new.employee_id,'employee','Extra break allowance exceeded','Only one extra break is allowed each day. Your break has been recorded for review.','break_policy','employee-extra-break-policy:'||new.id||':'||idx,'High');
 end if;
 end if;
 if item->>'end' is not null then
 if rec.id is null or rec.ended_at is null then
 insert into public.activity_events(employee_id,kind,title,occurred_at,event_key) values(new.employee_id,'break_end',label||' resumed work',(item->>'end')::timestamptz,'break-end:'||new.id||':'||idx) on conflict(event_key) do nothing;
 perform public.queue_notification(null,'admin',label||' resumed work','Break end recorded.','break','break-end:'||new.id||':'||idx);
 end if;
 update public.break_records set ended_at=(item->>'end')::timestamptz where shift_id=new.id and break_index=idx;
 -- A reminder is cancelled only when the actual break ended before its threshold.
 update public.notifications set cancelled_at=now() where event_key in('break-reminder:'||new.id||':'||idx,'admin-break-reminder:'||new.id||':'||idx) and available_at>(item->>'end')::timestamptz;
 end if;
 idx:=idx+1;
 end loop;return new;end$$;
create trigger montme_attendance_events after insert or update of ended_at,breaks on public.shift_records for each row execute function public.attendance_events();
create function public.call_activity() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' or old.outcome is distinct from new.outcome or old.duration_seconds is distinct from new.duration_seconds then
 insert into public.activity_events(employee_id,kind,title,occurred_at,detail) values(new.employee_id,case when tg_op='INSERT' then 'call_logged' else 'call_updated' end,'Business call: '||new.outcome,new.started_at,jsonb_build_object('call_id',new.id,'duration_seconds',new.duration_seconds,'source',new.source));end if;return new;end$$;
create trigger montme_call_activity after insert or update on public.call_records for each row execute function public.call_activity();
create function public.set_notification_read(notification_input uuid,read_input boolean) returns void language plpgsql security definer set search_path='' as $$declare n public.notifications;eid uuid:=public.employee_id();begin
 select * into n from public.notifications where id=notification_input and cancelled_at is null and available_at<=now();
 if n.id is null or not coalesce((n.audience='employee' and n.employee_id=eid) or (n.audience='admin' and public.has_permission('activity.view')),false) then raise exception 'Notification not available.';end if;
 insert into public.notification_receipts(notification_id,user_id,read_at,first_read_at) values(n.id,auth.uid(),case when read_input then now() end,case when read_input then now() end)
 on conflict(notification_id,user_id) do update set read_at=case when read_input then now() end,first_read_at=coalesce(public.notification_receipts.first_read_at,case when read_input then now() end);
 end$$;
create function public.send_team_notification(title_input text,body_input text,recipient_ids uuid[],priority_input text default 'Normal') returns void language plpgsql security definer set search_path='' as $$declare eid uuid;batch uuid:=gen_random_uuid();begin
 if not public.has_permission('notifications.manage') then raise exception 'Notification management permission required.';end if;
 if trim(title_input)='' or coalesce(cardinality(recipient_ids),0)=0 then raise exception 'Title and recipients are required.';end if;
 foreach eid in array recipient_ids loop
 if not exists(select 1 from public.employees where id=eid and active) then raise exception 'Recipient is inactive or missing.';end if;
 perform public.queue_notification(eid,'employee',title_input,body_input,'message','message:'||batch||':'||eid,priority_input);
 end loop;end$$;
create function public.register_push_device(token_input text) returns void language plpgsql security definer set search_path='' as $$begin
 if public.employee_id() is null and not public.is_admin() then raise exception 'Active account required.';end if;
 if length(token_input) not between 20 and 4096 then raise exception 'Invalid device token.';end if;
 insert into public.push_devices(user_id,token) values(auth.uid(),token_input) on conflict(token) do update set user_id=auth.uid(),updated_at=now();end$$;
create function public.unregister_push_device(token_input text) returns void language sql security definer set search_path='' as $$delete from public.push_devices where user_id=auth.uid() and token=token_input$$;
revoke all on function public.set_notification_read(uuid,boolean),public.send_team_notification(text,text,uuid[],text),public.register_push_device(text),public.unregister_push_device(text) from public;
grant execute on function public.set_notification_read(uuid,boolean),public.send_team_notification(text,text,uuid[],text),public.register_push_device(text),public.unregister_push_device(text) to authenticated;
-- Trusted worker only: claim an atomic, bounded batch for retry-safe delivery.
create function public.claim_notification_deliveries(batch_size integer default 30) returns setof public.notification_deliveries language plpgsql security definer set search_path='' as $$begin
 return query update public.notification_deliveries d set status='processing',locked_at=now(),attempts=attempts+1 where d.id in(
 select x.id from public.notification_deliveries x join public.notifications n on n.id=x.notification_id where ((x.status in('pending','retry') and x.available_at<=now()) or (x.status='processing' and x.locked_at<now()-interval '5 minutes')) and n.available_at<=now() and n.cancelled_at is null and x.attempts<8 order by x.available_at for update of x skip locked limit least(greatest(batch_size,1),100)) returning d.*;end$$;
create function public.notification_targets(notification_input uuid) returns table(user_id uuid,email text) language sql security definer set search_path='' as $$
 select u.id,u.email::text from public.notifications n join public.employees e on e.id=n.employee_id join auth.users u on u.id=e.auth_id where n.id=notification_input and n.audience='employee' and e.active
 union
 select u.id,u.email::text from public.notifications n join auth.users u on true where n.id=notification_input and n.audience='admin' and (exists(select 1 from public.app_admins a where a.user_id=u.id) or exists(select 1 from public.employees e join public.workspace_roles r on r.id=e.role_id where e.auth_id=u.id and e.active and 'activity.view'=any(r.permissions)))$$;
revoke all on function public.claim_notification_deliveries(integer),public.notification_targets(uuid) from public,anon,authenticated;
grant execute on function public.claim_notification_deliveries(integer),public.notification_targets(uuid) to service_role;
-- Fix editing/cancelling an assignment whose former recipient is now inactive.
create or replace function public.validate_assignment() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='INSERT' or new.recipient_ids is distinct from old.recipient_ids then
 if cardinality(new.recipient_ids)<>(select count(*) from public.employees where id=any(new.recipient_ids) and active) then raise exception 'Choose unique, active employees.';end if;end if;
 if cardinality(new.content_ids)<>(select count(*) from public.content_items where id=any(new.content_ids)) then raise exception 'One or more attachments are missing or duplicated.';end if;return new;end$$;
-- Granular permissions are enforced in the database, not only by navigation.
drop policy employee_admin_write on public.employees;
revoke insert,update,delete on public.employees from authenticated;
drop policy employee_read on public.employees;
create policy employee_read on public.employees for select to authenticated using(id=public.employee_id() or public.has_permission('employees.manage') or public.has_permission('activity.view') or public.has_permission('assignments.manage') or public.has_permission('contacts.manage') or public.has_permission('notifications.manage'));
drop policy contact_admin_write on public.contacts;drop policy contact_read on public.contacts;
create policy contact_read on public.contacts for select to authenticated using(public.has_permission('contacts.manage') or public.has_permission('activity.view') or assigned_employee_id=public.employee_id());
create policy contact_manage on public.contacts for all to authenticated using(public.has_permission('contacts.manage')) with check(public.has_permission('contacts.manage'));
drop policy assignment_admin on public.assignments;
create policy assignment_manage on public.assignments for all to authenticated using(public.has_permission('assignments.manage')) with check(public.has_permission('assignments.manage'));
create policy assignment_monitor on public.assignments for select to authenticated using(public.has_permission('activity.view'));
drop policy content_admin on public.content_items;
create policy content_manage on public.content_items for all to authenticated using(public.has_permission('assignments.manage')) with check(public.has_permission('assignments.manage'));
drop policy receipt_read on public.assignment_receipts;
create policy receipt_read on public.assignment_receipts for select to authenticated using(public.has_permission('activity.view') or public.has_permission('assignments.manage') or employee_id=public.employee_id());
drop policy call_read on public.call_records;create policy call_read on public.call_records for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
drop policy shift_read on public.shift_records;create policy shift_read on public.shift_records for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
drop policy montme_storage_admin on storage.objects;
create policy montme_storage_manage on storage.objects for all to authenticated using(bucket_id='montme-content' and public.has_permission('assignments.manage')) with check(bucket_id='montme-content' and public.has_permission('assignments.manage'));
do $$declare t text;begin foreach t in array array['workspace_roles','workspace_settings','activity_events','break_records','notifications','notification_receipts','notification_deliveries','push_devices','login_rate_limits'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);end loop;end$$;
create policy role_read on public.workspace_roles for select to authenticated using(public.employee_id() is not null or public.is_admin());
create policy role_manage on public.workspace_roles for all to authenticated using(public.has_permission('roles.manage')) with check(public.has_permission('roles.manage'));
create policy setting_read on public.workspace_settings for select to authenticated using(public.employee_id() is not null or public.is_admin());
create policy setting_manage on public.workspace_settings for update to authenticated using(public.has_permission('settings.manage')) with check(public.has_permission('settings.manage'));
create policy activity_read on public.activity_events for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
create policy break_read on public.break_records for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
create policy notification_read on public.notifications for select to authenticated using(public.has_permission('notifications.manage') or public.has_permission('activity.view') or (audience='employee' and employee_id=public.employee_id() and cancelled_at is null and available_at<=now()));
create policy notification_receipt_read on public.notification_receipts for select to authenticated using(user_id=auth.uid() or public.has_permission('notifications.manage') or public.has_permission('activity.view'));
create policy delivery_read on public.notification_deliveries for select to authenticated using(public.has_permission('notifications.manage'));
grant select,insert,update,delete on public.workspace_roles to authenticated;
grant select,update on public.workspace_settings to authenticated;
grant select on public.activity_events,public.break_records,public.notifications,public.notification_receipts,public.notification_deliveries to authenticated;
-- Service-only records have RLS enabled and no client policies/grants.
insert into public.schema_migrations(version) values('20261118_004_people_notifications');
commit;
