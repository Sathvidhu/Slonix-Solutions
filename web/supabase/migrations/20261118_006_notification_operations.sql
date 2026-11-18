-- Operational improvements; no existing records are removed.
begin;
create function public.retry_notification_deliveries() returns integer language plpgsql security definer set search_path='' as $$declare total integer;begin
 if not public.has_permission('notifications.manage') then raise exception 'Notification permission required.';end if;
 update public.notification_deliveries d set status='pending',attempts=0,available_at=now(),last_error=null,locked_at=null where d.status in('blocked','failed','skipped') and exists(select 1 from public.notifications n where n.id=d.notification_id and n.cancelled_at is null and n.available_at<=now());get diagnostics total=row_count;return total;end$$;
revoke all on function public.retry_notification_deliveries() from public;
grant execute on function public.retry_notification_deliveries() to authenticated;
create or replace function public.refresh_attendance_notifications() returns void language plpgsql security definer set search_path='' as $$declare r record;settings public.workspace_settings;day_input date:=(now() at time zone 'Asia/Kolkata')::date;start_input timestamptz;end_input timestamptz;begin
 select * into settings from public.workspace_settings where id;
 for r in select distinct e.id from public.employees e join public.shift_records s on s.employee_id=e.id where e.active and s.ended_at is null loop
 start_input:=(day_input+settings.lunch_start) at time zone 'Asia/Kolkata';end_input:=(day_input+settings.lunch_end) at time zone 'Asia/Kolkata';
 if now()>=start_input and now()<end_input then perform public.queue_notification(r.id,'employee','Lunch break window is open','Lunch window: '||to_char(settings.lunch_start,'HH12:MI AM')||' to '||to_char(settings.lunch_end,'HH12:MI AM')||' IST. Record your actual break in Montme.','break_window','lunch-window:'||r.id||':'||day_input,'Normal',start_input);end if;
 start_input:=(day_input+settings.evening_start) at time zone 'Asia/Kolkata';end_input:=(day_input+settings.evening_end) at time zone 'Asia/Kolkata';
 if now()>=start_input and now()<end_input then perform public.queue_notification(r.id,'employee','Evening break window is open','Evening window: '||to_char(settings.evening_start,'HH12:MI AM')||' to '||to_char(settings.evening_end,'HH12:MI AM')||' IST. Record your actual break in Montme.','break_window','evening-window:'||r.id||':'||day_input,'Normal',start_input);end if;
 end loop;
 -- Include open breaks carried over from the previous app version.
 for r in select b.*,e.name from public.break_records b join public.employees e on e.id=b.employee_id join public.shift_records s on s.id=b.shift_id where b.ended_at is null and s.ended_at is null and e.active and b.deadline_at<=now() loop
 perform public.queue_notification(r.employee_id,'employee',initcap(r.kind)||' break exceeded','Your allowed break time has elapsed. Return to Montme to resume work.','break_reminder','break-reminder:'||r.shift_id||':'||r.break_index,'High',r.deadline_at);
 perform public.queue_notification(null,'admin',r.name||' - '||r.kind||' break exceeded','The recorded break is still open beyond its allowed time.','break_reminder','admin-break-reminder:'||r.shift_id||':'||r.break_index,'High',r.deadline_at);
 end loop;end$$;
insert into public.schema_migrations(version) values('20261118_006_notification_operations');
commit;
