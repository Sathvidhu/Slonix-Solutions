-- Run after migration 004. Requires Supabase Cron and pg_net extensions.
-- In-app window reminders work without an external email/push provider.
create or replace function public.refresh_attendance_notifications() returns void language plpgsql security definer set search_path='' as $$declare r record;settings public.workspace_settings;day_input date:=(now() at time zone 'Asia/Kolkata')::date;start_input timestamptz;end_input timestamptz;begin
 select * into settings from public.workspace_settings where id;
 for r in select distinct e.id from public.employees e join public.shift_records s on s.employee_id=e.id where e.active and s.ended_at is null loop
 start_input:=(day_input+settings.lunch_start) at time zone 'Asia/Kolkata';end_input:=(day_input+settings.lunch_end) at time zone 'Asia/Kolkata';
 if now()>=start_input and now()<end_input then perform public.queue_notification(r.id,'employee','Lunch break window is open','Lunch is scheduled from 1:30 PM to 2:30 PM. Start your break in Montme when you stop working.','break_window','lunch-window:'||r.id||':'||day_input,'Normal',start_input);end if;
 start_input:=(day_input+settings.evening_start) at time zone 'Asia/Kolkata';end_input:=(day_input+settings.evening_end) at time zone 'Asia/Kolkata';
 if now()>=start_input and now()<end_input then perform public.queue_notification(r.id,'employee','Evening break window is open','Evening break is scheduled from 5:00 PM to 5:30 PM. Start your break in Montme when you stop working.','break_window','evening-window:'||r.id||':'||day_input,'Normal',start_input);end if;
 end loop;end$$;
revoke all on function public.refresh_attendance_notifications() from public,anon,authenticated;
grant execute on function public.refresh_attendance_notifications() to service_role;
-- Dispatcher needs this function even before Cron is enabled.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create or replace function public.montme_notification_tick() returns void language plpgsql security definer set search_path='' as $$declare worker_secret text;begin
 perform public.refresh_attendance_notifications();
 select decrypted_secret into worker_secret from vault.decrypted_secrets where name='montme_dispatch_secret' limit 1;
 if worker_secret is not null then perform net.http_post(url:='https://xnbqhzawxnjflhoskkds.supabase.co/functions/v1/deliver-notifications',headers:=jsonb_build_object('Content-Type','application/json','x-dispatch-secret',worker_secret),body:='{}'::jsonb,timeout_milliseconds:=10000);end if;
 end$$;
revoke all on function public.montme_notification_tick() from public,anon,authenticated;
do $$begin if not exists(select 1 from cron.job where jobname='montme-notification-delivery') then perform cron.schedule('montme-notification-delivery','* * * * *','select public.montme_notification_tick()');end if;end$$;
