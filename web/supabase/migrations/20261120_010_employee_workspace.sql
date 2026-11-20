begin;

alter table public.employees
  add column display_name text check (length(btrim(display_name)) between 1 and 120),
  add column clock_out_time time(0);
alter table public.workspace_settings
  add column company_name text not null default 'Montme' check (length(btrim(company_name)) between 1 and 120);
create unique index shift_one_open_per_employee
  on public.shift_records(employee_id) where ended_at is null;

create table public.daily_work_reports (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null unique references public.shift_records(id),
  employee_id uuid not null references public.employees(id),
  work_day date not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  breaks jsonb not null,
  calls jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.daily_work_reports enable row level security;
create policy daily_report_read on public.daily_work_reports for select to authenticated
  using (employee_id = public.employee_id() or public.has_permission('activity.view'));
grant select on public.daily_work_reports to authenticated;
grant all on public.daily_work_reports to service_role;

create function public.set_my_display_name(name_input text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.employee_id() is null or coalesce(length(btrim(name_input)),0) not between 1 and 120 then
    raise exception 'Enter a display name between 1 and 120 characters.';
  end if;
  update public.employees set display_name=btrim(name_input) where id=public.employee_id();
end $$;

create function public.set_employee_clock_out(employee_input uuid, time_input time) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not public.has_permission('employees.manage') then raise exception 'Employee management permission required.'; end if;
  update public.employees set clock_out_time=time_input where id=employee_input;
  if not found then raise exception 'Employee not found.'; end if;
end $$;

create function public.clock_in() returns public.shift_records
language plpgsql security definer set search_path='' as $$
declare eid uuid := public.employee_id(); shift public.shift_records;
begin
  if eid is null then raise exception 'Active employee sign-in required.'; end if;
  perform 1 from public.employees where id=eid for update;
  select * into shift from public.shift_records where employee_id=eid and ended_at is null;
  if found then return shift; end if;
  insert into public.shift_records(employee_id,device_shift_id,started_at)
    values(eid,gen_random_uuid()::text,clock_timestamp()) returning * into shift;
  return shift;
end $$;

create function public.toggle_shift_break(shift_input text, expected_input jsonb, kind_input text default null)
returns public.shift_records language plpgsql security definer set search_path='' as $$
declare
  shift public.shift_records;
  stamp timestamptz;
  kind text;
begin
  select * into shift from public.shift_records
    where employee_id=public.employee_id() and device_shift_id=shift_input for update;
  if not found or shift.ended_at is not null or shift.breaks is distinct from public.normalize_break_json(expected_input)
    then raise exception 'The shift changed. Refresh and try again.'; end if;
  stamp := clock_timestamp();
  if jsonb_array_length(shift.breaks)>0 and shift.breaks->-1->>'end' is null then
    shift.breaks := jsonb_set(shift.breaks, '{-1,end}', to_jsonb(stamp));
  else
    kind := coalesce(kind_input, public.break_kind(stamp));
    if kind not in ('extra','lunch','evening') or
      (kind<>'extra' and kind<>public.break_kind(stamp)) then
      raise exception 'That break type is outside its scheduled window.';
    end if;
    if kind='extra' and exists(
      select 1 from public.break_records b where b.employee_id=shift.employee_id and b.kind='extra'
      and (b.started_at at time zone 'Asia/Kolkata')::date=(stamp at time zone 'Asia/Kolkata')::date
    ) then raise exception 'Your one extra break for today has already been used.'; end if;
    shift.breaks := shift.breaks || jsonb_build_array(jsonb_build_object(
      'start',stamp,'end',null,'kind',kind,'deadline',public.break_deadline(stamp,kind)));
  end if;
  update public.shift_records set breaks=shift.breaks where id=shift.id returning * into shift;
  return shift;
end $$;

create function public.register_web_push(token_input text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.employee_id() is null or coalesce(length(token_input),0) not between 20 and 4096
    then raise exception 'Active employee and a valid push token required.'; end if;
  insert into public.push_devices(user_id,token,platform) values(auth.uid(),token_input,'web')
    on conflict(token) do update set user_id=auth.uid(), platform='web', updated_at=now();
end $$;

create function public.submit_daily_report(shift_input text) returns public.shift_records
language plpgsql security definer set search_path='' as $$
declare
  eid uuid := public.employee_id();
  shift public.shift_records;
  finished timestamptz;
  cutoff time;
  eligible_at timestamptz;
  work_day date;
  call_snapshot jsonb;
begin
  select * into shift from public.shift_records
    where employee_id=eid and device_shift_id=shift_input for update;
  if not found then raise exception 'Shift not found.'; end if;
  if shift.ended_at is not null then
    if exists(select 1 from public.daily_work_reports r where r.shift_id=shift.id) then return shift; end if;
    raise exception 'This shift was already closed.';
  end if;

  finished := clock_timestamp();
  work_day := (shift.started_at at time zone 'Asia/Kolkata')::date;
  select clock_out_time into cutoff from public.employees where id=eid;
  eligible_at := coalesce((work_day + cutoff) at time zone 'Asia/Kolkata', shift.started_at + interval '2 hours');
  if finished < eligible_at then
    update public.early_exit_requests set status='used'
      where employee_id=eid and device_shift_id=shift_input and status='approved';
    if not found then raise exception 'An admin approval is required before early clock-out.'; end if;
  end if;

  if jsonb_array_length(shift.breaks)>0 and shift.breaks->-1->>'end' is null then
    shift.breaks := jsonb_set(shift.breaks, '{-1,end}', to_jsonb(finished));
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object('lead_name', c.lead_name, 'phone', c.phone, 'started_at', c.started_at,
      'duration_seconds', c.duration_seconds, 'direction', c.direction, 'source', c.source,
      'outcome', c.outcome, 'notes', c.notes)
    order by c.started_at, c.id), '[]'::jsonb)
    into call_snapshot from public.call_records c
    where c.employee_id=eid and c.started_at between shift.started_at and finished;

  insert into public.daily_work_reports(shift_id,employee_id,work_day,started_at,ended_at,breaks,calls)
    values(shift.id,eid,work_day,shift.started_at,finished,shift.breaks,call_snapshot);
  update public.shift_records set ended_at=finished,breaks=shift.breaks
    where id=shift.id returning * into shift;
  return shift;
end $$;

create or replace function public.submission_alert() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform public.queue_notification(null,'admin','Employee report uploaded',
    coalesce((select name from public.employees where id=new.employee_id),'Employee') ||
      ' uploaded ' || new.file_name || '. Review it in Daily Work Reports.',
    'submission','submission:'||new.id,'High');
  return new;
end $$;

-- Attendance writes go through the shared functions, including on Android.
revoke insert,update on public.shift_records from authenticated;
revoke execute on function public.consume_early_exit(text) from authenticated;
revoke all on function public.clock_in(), public.toggle_shift_break(text,jsonb,text), public.register_web_push(text),
  public.submit_daily_report(text), public.set_my_display_name(text),
  public.set_employee_clock_out(uuid,time) from public,anon;
grant execute on function public.clock_in(), public.toggle_shift_break(text,jsonb,text), public.register_web_push(text),
  public.submit_daily_report(text), public.set_my_display_name(text),
  public.set_employee_clock_out(uuid,time) to authenticated;

commit;
