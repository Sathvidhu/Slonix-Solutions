-- Preserve calls to device-created leads and support reviewed early exits and report submissions.
begin;
alter table public.call_records add column if not exists lead_name text not null default '';
create table public.early_exit_requests(id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id),device_shift_id text not null,reason text not null check(length(reason) between 1 and 1000),status text not null default 'pending' check(status in ('pending','approved','dismissed','used')),decision_note text not null default '',decided_by uuid references auth.users(id),decided_at timestamptz,created_at timestamptz not null default now(),unique(employee_id,device_shift_id));
create table public.work_submissions(id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.employees(id),file_path text not null unique,file_name text not null,mime_type text not null,size_bytes integer not null check(size_bytes between 1 and 20971520),note text not null default '' check(length(note)<=1000),created_at timestamptz not null default now());
alter table public.early_exit_requests enable row level security;
alter table public.work_submissions enable row level security;
create policy exit_read on public.early_exit_requests for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
create policy submission_read on public.work_submissions for select to authenticated using(public.has_permission('activity.view') or employee_id=public.employee_id());
create policy submission_insert on public.work_submissions for insert to authenticated with check(employee_id=public.employee_id() and file_path like employee_id::text || '/%' and exists(select 1 from storage.objects o where o.bucket_id='montme-submissions' and o.name=file_path));
grant select on public.early_exit_requests to authenticated;
grant select,insert on public.work_submissions to authenticated;
grant all on public.early_exit_requests,public.work_submissions to service_role;
insert into storage.buckets(id,name,public,file_size_limit)values('montme-submissions','montme-submissions',false,20971520) on conflict(id) do nothing;
create policy submission_file_insert on storage.objects for insert to authenticated with check(bucket_id='montme-submissions' and name like public.employee_id()::text || '/%');
create policy submission_file_read on storage.objects for select to authenticated using(bucket_id='montme-submissions' and (public.has_permission('activity.view') or name like public.employee_id()::text || '/%'));
create policy submission_file_cleanup on storage.objects for delete to authenticated using(bucket_id='montme-submissions' and name like public.employee_id()::text || '/%' and not exists(select 1 from public.work_submissions s where s.file_path=name));
create function public.request_early_exit(shift_input text,reason_input text) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid:=public.employee_id();rid uuid;begin
 if eid is null then raise exception 'Active employee sign-in required.';end if;
 if not exists(select 1 from public.shift_records where employee_id=eid and device_shift_id=shift_input and ended_at is null) then raise exception 'Sync your open shift before requesting early clock-out.';end if;
 insert into public.early_exit_requests(employee_id,device_shift_id,reason)values(eid,shift_input,btrim(reason_input)) returning id into rid;
 perform public.queue_notification(null,'admin','Early clock-out requested',coalesce((select name from public.employees where id=eid),'Employee') || ': ' || reason_input,'early_exit','exit-request:'||rid,'High');return rid;end$$;
create function public.decide_early_exit(request_input uuid,approve_input boolean,note_input text default '') returns void language plpgsql security definer set search_path='' as $$declare r public.early_exit_requests;begin
 if not public.has_permission('activity.view') then raise exception 'Activity permission required.';end if;
 if length(note_input)>1000 then raise exception 'Decision note is too long.';end if;
 select * into r from public.early_exit_requests where id=request_input for update;
 if r.id is null or r.status<>'pending' then raise exception 'Request is no longer pending.';end if;
 if not exists(select 1 from public.shift_records where employee_id=r.employee_id and device_shift_id=r.device_shift_id and ended_at is null) then raise exception 'Shift is already closed.';end if;
 update public.early_exit_requests set status=case when approve_input then 'approved' else 'dismissed' end,decision_note=note_input,decided_by=auth.uid(),decided_at=now() where id=r.id;
 perform public.queue_notification(r.employee_id,'employee',case when approve_input then 'Early clock-out approved' else 'Early clock-out dismissed' end,case when approve_input then 'Your admin approved this shift. You can now clock out.' else 'Your admin dismissed this request. Your shift continues.' end || case when note_input<>'' then E'\nAdmin note: '||note_input else '' end,'early_exit','exit-decision:'||r.id,'High');end$$;
create function public.consume_early_exit(shift_input text) returns void language plpgsql security definer set search_path='' as $$begin
 update public.early_exit_requests set status='used' where employee_id=public.employee_id() and device_shift_id=shift_input and status='approved';
 if not found then raise exception 'An admin approval is required before early clock-out.';end if;end$$;
create function public.submission_alert() returns trigger language plpgsql security definer set search_path='' as $$begin perform public.queue_notification(null,'admin','Employee report uploaded',coalesce((select name from public.employees where id=new.employee_id),'Employee') || ' uploaded ' || new.file_name || '. Review it in Activity.','submission','submission:'||new.id,'High');return new;end$$;
create trigger montme_submission_alert after insert on public.work_submissions for each row execute function public.submission_alert();
revoke all on function public.request_early_exit(text,text),public.decide_early_exit(uuid,boolean,text),public.consume_early_exit(text),public.submission_alert() from public,anon;
grant execute on function public.request_early_exit(text,text),public.decide_early_exit(uuid,boolean,text),public.consume_early_exit(text) to authenticated;
commit;
