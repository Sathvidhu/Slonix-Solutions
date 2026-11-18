-- Montme / single-company workspace. Run once in Supabase SQL Editor.
-- First create slonixbim.team@gmail.com in Authentication > Users > Add user.
-- Use the requested admin password there and enable Auto Confirm User.
begin;
create extension if not exists pgcrypto;
create table public.app_admins(user_id uuid primary key references auth.users(id) on delete cascade,username text not null unique,created_at timestamptz not null default now());
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.app_admins where user_id=auth.uid())$$;
revoke all on function public.is_admin() from public;grant execute on function public.is_admin() to authenticated;
create table public.employees(id uuid primary key default gen_random_uuid(),auth_id uuid unique references auth.users(id) on delete set null,name text not null check(length(trim(name))>0),email text not null unique check(email=lower(email)),employee_code text not null unique,phone text not null default '',role text not null default 'Employee',active boolean not null default true,created_at timestamptz not null default now());
create function public.employee_id() returns uuid language sql stable security definer set search_path='' as $$select id from public.employees where auth_id=auth.uid() and active limit 1$$;
revoke all on function public.employee_id() from public;grant execute on function public.employee_id() to authenticated;
create table public.contacts(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name))>0),company text not null default '',phone text not null,email text not null default '',status text not null default 'New' check(status in ('New','Contacted','Interested','Follow-up','Won','Not interested')),notes text not null default '',assigned_employee_id uuid references public.employees(id) on delete set null,follow_up_at timestamptz,created_at timestamptz not null default now());
create unique index contact_phone_key on public.contacts(regexp_replace(phone,'[^0-9]','','g'));
create table public.content_items(id uuid primary key default gen_random_uuid(),title text not null check(length(trim(title))>0),kind text not null check(kind in ('text','link','file')),body text not null default '',file_path text unique,file_name text,mime_type text,size_bytes bigint check(size_bytes between 0 and 20971520),created_at timestamptz not null default now(),check((kind='file' and file_path is not null and file_name is not null) or (kind<>'file' and file_path is null)),check(kind<>'link' or body ~ '^https?://'));
create table public.assignments(id uuid primary key default gen_random_uuid(),title text not null check(length(trim(title))>0),message text not null default '',recipient_ids uuid[] not null check(cardinality(recipient_ids)>0),content_ids uuid[] not null default '{}',priority text not null default 'Normal' check(priority in ('Normal','High','Urgent')),state text not null default 'published' check(state in ('published','draft','cancelled')),release_at timestamptz not null default now(),due_at timestamptz,series_id uuid,repeat_rule text not null default 'none' check(repeat_rule in ('none','daily','weekly','monthly')),created_at timestamptz not null default now(),check(due_at is null or due_at>=release_at));
create index assignment_recipients on public.assignments using gin(recipient_ids);
create index assignment_release on public.assignments(release_at);
create table public.assignment_receipts(id uuid primary key default gen_random_uuid(),assignment_id uuid not null references public.assignments(id) on delete cascade,employee_id uuid not null references public.employees(id),status text not null check(status in ('read','completed')),read_at timestamptz not null default now(),completed_at timestamptz,created_at timestamptz not null default now(),unique(assignment_id,employee_id));
create table public.call_records(id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id),contact_id uuid references public.contacts(id) on delete set null,device_call_id text not null,phone text not null,started_at timestamptz not null,duration_seconds integer not null check(duration_seconds>=0),direction text not null check(direction in ('Incoming','Outgoing','Missed','Rejected')),source text not null check(source in ('Manual','Android')),outcome text not null default 'Not reviewed',notes text not null default '',created_at timestamptz not null default now(),unique(employee_id,device_call_id));
create table public.shift_records(id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id),device_shift_id text not null,started_at timestamptz not null,ended_at timestamptz,breaks jsonb not null default '[]',created_at timestamptz not null default now(),unique(employee_id,device_shift_id),check(ended_at is null or ended_at>=started_at));
create table public.audit_events(id bigint generated always as identity primary key,actor_id uuid,entity text not null,entity_id text,action text not null,created_at timestamptz not null default now());
create function public.audit_change() returns trigger language plpgsql security definer set search_path='' as $$begin insert into public.audit_events(actor_id,entity,entity_id,action) values(auth.uid(),tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),tg_op);return coalesce(new,old);end$$;
create function public.link_employee_auth() returns trigger language plpgsql security definer set search_path='' as $$begin update public.employees set auth_id=new.id where email=lower(new.email) and auth_id is null;return new;end$$;
create trigger montme_link_employee after insert on auth.users for each row execute function public.link_employee_auth();
create function public.link_existing_employee() returns trigger language plpgsql security definer set search_path='' as $$begin if new.auth_id is null then select id into new.auth_id from auth.users where lower(email)=new.email;end if;return new;end$$;
create trigger montme_existing_employee before insert on public.employees for each row execute function public.link_existing_employee();
create function public.validate_assignment() returns trigger language plpgsql set search_path='' as $$begin
 if cardinality(new.recipient_ids)<>(select count(*) from public.employees where id=any(new.recipient_ids) and active) then raise exception 'Choose unique, active employees.';end if;
 if cardinality(new.content_ids)<>(select count(*) from public.content_items where id=any(new.content_ids)) then raise exception 'One or more attachments are missing or duplicated.';end if;
 return new;end$$;
create trigger montme_validate_assignment before insert or update on public.assignments for each row execute function public.validate_assignment();
-- A batch is atomic: a repeating schedule is saved completely or not at all.
create function public.create_assignment_batch(items jsonb) returns void language plpgsql security invoker set search_path='' as $$declare item jsonb;begin
 if not public.is_admin() then raise exception 'Admin access required.';end if;
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items) not between 1 and 367 then raise exception 'Invalid assignment batch.';end if;
 for item in select value from jsonb_array_elements(items) loop
 insert into public.assignments(title,message,recipient_ids,content_ids,priority,state,release_at,due_at,series_id,repeat_rule)
 values(item->>'title',coalesce(item->>'message',''),array(select jsonb_array_elements_text(item->'recipient_ids')::uuid),array(select jsonb_array_elements_text(coalesce(item->'content_ids','[]'::jsonb))::uuid),coalesce(item->>'priority','Normal'),coalesce(item->>'state','published'),(item->>'release_at')::timestamptz,(item->>'due_at')::timestamptz,(item->>'series_id')::uuid,coalesce(item->>'repeat_rule','none'));
 end loop;end$$;
create function public.acknowledge_assignment(assignment_id_input uuid,status_input text) returns void language plpgsql security definer set search_path='' as $$declare eid uuid:=public.employee_id();begin
 if eid is null or status_input not in ('read','completed') then raise exception 'Invalid acknowledgement.';end if;
 if not exists(select 1 from public.assignments where id=assignment_id_input and eid=any(recipient_ids) and state='published' and release_at<=now()) then raise exception 'Assignment not available.';end if;
 insert into public.assignment_receipts(assignment_id,employee_id,status,completed_at) values(assignment_id_input,eid,status_input,case when status_input='completed' then now() else null end)
 on conflict(assignment_id,employee_id) do update set status=case when public.assignment_receipts.status='completed' then 'completed' else excluded.status end,completed_at=coalesce(public.assignment_receipts.completed_at,excluded.completed_at);
 end$$;
revoke all on function public.create_assignment_batch(jsonb),public.acknowledge_assignment(uuid,text) from public;
grant execute on function public.create_assignment_batch(jsonb),public.acknowledge_assignment(uuid,text) to authenticated;
do $$declare t text;begin foreach t in array array['app_admins','employees','contacts','content_items','assignments','assignment_receipts','call_records','shift_records','audit_events'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon',t);end loop;end$$;
create policy admin_self on public.app_admins for select to authenticated using(user_id=auth.uid());
create policy employee_read on public.employees for select to authenticated using(public.is_admin() or (id=public.employee_id()));
create policy employee_admin_write on public.employees for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy contact_read on public.contacts for select to authenticated using(public.is_admin() or assigned_employee_id=public.employee_id());
create policy contact_admin_write on public.contacts for all to authenticated using(public.is_admin()) with check(public.is_admin());
-- Employees can update lead outcome/notes, but not assignment or phone numbers.
create function public.update_my_contact(contact_id_input uuid,status_input text,notes_input text,follow_up_input timestamptz default null) returns void language plpgsql security definer set search_path='' as $$begin update public.contacts set status=status_input,notes=notes_input,follow_up_at=follow_up_input where id=contact_id_input and assigned_employee_id=public.employee_id();if not found then raise exception 'Contact not assigned to you.';end if;end$$;
revoke all on function public.update_my_contact(uuid,text,text,timestamptz) from public;grant execute on function public.update_my_contact(uuid,text,text,timestamptz) to authenticated;
create policy assignment_admin on public.assignments for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy assignment_employee_read on public.assignments for select to authenticated using(public.employee_id()=any(recipient_ids) and state='published' and release_at<=now());
create policy content_admin on public.content_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy content_employee_read on public.content_items for select to authenticated using(exists(select 1 from public.assignments a where content_items.id=any(a.content_ids) and public.employee_id()=any(a.recipient_ids) and a.state='published' and a.release_at<=now()));
create policy receipt_read on public.assignment_receipts for select to authenticated using(public.is_admin() or employee_id=public.employee_id());
create policy call_read on public.call_records for select to authenticated using(public.is_admin() or employee_id=public.employee_id());
create policy call_write on public.call_records for insert to authenticated with check(employee_id=public.employee_id() and (contact_id is null or exists(select 1 from public.contacts c where c.id=contact_id and c.assigned_employee_id=public.employee_id())));
create policy call_update on public.call_records for update to authenticated using(employee_id=public.employee_id()) with check(employee_id=public.employee_id() and (contact_id is null or exists(select 1 from public.contacts c where c.id=contact_id and c.assigned_employee_id=public.employee_id())));
create policy shift_read on public.shift_records for select to authenticated using(public.is_admin() or employee_id=public.employee_id());
create policy shift_write on public.shift_records for insert to authenticated with check(employee_id=public.employee_id());
create policy shift_update on public.shift_records for update to authenticated using(employee_id=public.employee_id()) with check(employee_id=public.employee_id());
create policy audit_read on public.audit_events for select to authenticated using(public.is_admin());
grant select on public.app_admins,public.assignment_receipts,public.audit_events to authenticated;
grant select,insert,update,delete on public.employees,public.contacts,public.content_items,public.assignments to authenticated;
grant select,insert,update on public.call_records,public.shift_records to authenticated;
-- No direct writes to receipts or role tables.
revoke insert,update,delete on public.app_admins,public.assignment_receipts,public.audit_events from authenticated;
-- Keep used content available: reject deletion instead of leaving broken attachments.
create function public.protect_content() returns trigger language plpgsql set search_path='' as $$begin if exists(select 1 from public.assignments where old.id=any(content_ids)) then raise exception 'Content is used in an assignment.';end if;return old;end$$;
create trigger montme_protect_content before delete on public.content_items for each row execute function public.protect_content();
do $$declare t text;begin foreach t in array array['employees','contacts','content_items','assignments'] loop execute format('create trigger montme_audit after insert or update or delete on public.%I for each row execute function public.audit_change()',t);end loop;end$$;
insert into storage.buckets(id,name,public,file_size_limit) values('montme-content','montme-content',false,20971520) on conflict(id) do update set public=false,file_size_limit=20971520;
create policy montme_storage_admin on storage.objects for all to authenticated using(bucket_id='montme-content' and public.is_admin()) with check(bucket_id='montme-content' and public.is_admin());
create policy montme_storage_employee on storage.objects for select to authenticated using(bucket_id='montme-content' and exists(select 1 from public.content_items c join public.assignments a on c.id=any(a.content_ids) where c.file_path=name and public.employee_id()=any(a.recipient_ids) and a.state='published' and a.release_at<=now()));
-- Bootstrap only this verified owner. Does not create or store a password.
do $$declare admin_id uuid;begin select id into admin_id from auth.users where lower(email)='slonixbim.team@gmail.com';if admin_id is null then raise exception 'First create slonixbim.team@gmail.com in Authentication > Users, then run this script again.';end if;insert into public.app_admins(user_id,username) values(admin_id,'lokesh');end$$;
commit;
