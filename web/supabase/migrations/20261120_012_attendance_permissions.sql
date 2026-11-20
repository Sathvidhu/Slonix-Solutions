begin;

alter table public.workspace_roles drop constraint workspace_roles_permissions_check;
alter table public.workspace_roles add constraint workspace_roles_permissions_check
  check (permissions <@ array[
    'employees.manage','roles.manage','contacts.manage','assignments.manage',
    'activity.view','notifications.manage','settings.manage','attendance.approve','reports.read'
  ]::text[]);

alter policy exit_read on public.early_exit_requests
  using (public.has_permission('attendance.approve') or employee_id=public.employee_id());
alter policy submission_read on public.work_submissions
  using (public.has_permission('reports.read') or employee_id=public.employee_id());
alter policy daily_report_read on public.daily_work_reports
  using (public.has_permission('reports.read') or employee_id=public.employee_id());
alter policy submission_file_read on storage.objects
  using (bucket_id='montme-submissions' and
    (public.has_permission('reports.read') or name like public.employee_id()::text || '/%'));

create or replace function public.decide_early_exit(request_input uuid,approve_input boolean,note_input text default '') returns void language plpgsql security definer set search_path='' as $$declare r public.early_exit_requests;begin
 if not public.has_permission('attendance.approve') then raise exception 'Attendance approval permission required.';end if;
 if length(note_input)>1000 then raise exception 'Decision note is too long.';end if;
 select * into r from public.early_exit_requests where id=request_input for update;
 if r.id is null or r.status<>'pending' then raise exception 'Request is no longer pending.';end if;
 if not exists(select 1 from public.shift_records where employee_id=r.employee_id and device_shift_id=r.device_shift_id and ended_at is null) then raise exception 'Shift is already closed.';end if;
 update public.early_exit_requests set status=case when approve_input then 'approved' else 'dismissed' end,decision_note=note_input,decided_by=auth.uid(),decided_at=now() where id=r.id;
 perform public.queue_notification(r.employee_id,'employee',case when approve_input then 'Early clock-out approved' else 'Early clock-out dismissed' end,case when approve_input then 'Your admin approved this shift. You can now clock out.' else 'Your admin dismissed this request. Your shift continues.' end || case when note_input<>'' then E'\nAdmin note: '||note_input else '' end,'early_exit','exit-decision:'||r.id,'High');end$$;

create function public.admin_notice_permission(kind_input text) returns text
language sql immutable set search_path='' as $$
  select case kind_input
    when 'early_exit' then 'attendance.approve'
    when 'submission' then 'reports.read'
    else 'activity.view'
  end;
$$;
revoke all on function public.admin_notice_permission(text) from public,anon;
grant execute on function public.admin_notice_permission(text) to authenticated;

alter policy notification_read on public.notifications using (
  case
    when audience='admin' and kind in ('early_exit','submission')
      then public.has_permission(public.admin_notice_permission(kind))
    else public.has_permission('notifications.manage') or public.has_permission('activity.view') or
      (audience='employee' and employee_id=public.employee_id() and cancelled_at is null and available_at<=now())
  end
);

create or replace function public.set_notification_read(notification_input uuid,read_input boolean) returns void language plpgsql security definer set search_path='' as $$declare n public.notifications;eid uuid:=public.employee_id();begin
 select * into n from public.notifications where id=notification_input and cancelled_at is null and available_at<=now();
 if n.id is null or not coalesce((n.audience='employee' and n.employee_id=eid) or (n.audience='admin' and public.has_permission(public.admin_notice_permission(n.kind))),false) then raise exception 'Notification not available.';end if;
 insert into public.notification_receipts(notification_id,user_id,read_at,first_read_at) values(n.id,auth.uid(),case when read_input then now() end,case when read_input then now() end)
 on conflict(notification_id,user_id) do update set read_at=case when read_input then now() end,first_read_at=coalesce(public.notification_receipts.first_read_at,case when read_input then now() end);
 end$$;

create or replace function public.notification_targets(notification_input uuid) returns table(user_id uuid,email text) language sql security definer set search_path='' as $$
 select u.id,u.email::text from public.notifications n join public.employees e on e.id=n.employee_id join auth.users u on u.id=e.auth_id where n.id=notification_input and n.audience='employee' and e.active
 union
 select u.id,u.email::text from public.notifications n join auth.users u on true where n.id=notification_input and n.audience='admin' and (exists(select 1 from public.app_admins a where a.user_id=u.id) or exists(select 1 from public.employees e join public.workspace_roles r on r.id=e.role_id where e.auth_id=u.id and e.active and public.admin_notice_permission(n.kind)=any(r.permissions)))$$;

commit;
