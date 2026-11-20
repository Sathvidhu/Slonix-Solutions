begin;

alter table public.contacts add column created_by_employee uuid references public.employees(id) on delete set null;

create function public.employee_lead_phone_key(phone_input text) returns text
language sql immutable set search_path='' as $$
  select right(regexp_replace(phone_input,'[^0-9]','','g'),10);
$$;

create function public.save_my_leads(leads_input jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare
  eid uuid := public.employee_id();
  item jsonb;
  lead_id uuid;
  name_value text;
  phone_value text;
  institution_value text;
  notes_value text;
  status_value text;
  follow_value timestamptz;
  edit_existing boolean;
  saved integer := 0;
begin
  if eid is null then raise exception 'Active employee sign-in required.'; end if;
  if jsonb_typeof(leads_input) is distinct from 'array' then raise exception 'Send a list of leads.'; end if;
  if jsonb_array_length(leads_input) not between 1 and 200 then raise exception 'Send 1 to 200 leads at a time.'; end if;

  perform 1 from public.employees where id=eid for update;
  for item in select value from jsonb_array_elements(leads_input) loop
    lead_id := (item->>'id')::uuid;
    edit_existing := coalesce((item->>'edit')::boolean,false);
    name_value := btrim(coalesce(item->>'name',''));
    phone_value := btrim(coalesce(item->>'phone',''));
    institution_value := btrim(coalesce(item->>'institution',''));
    notes_value := coalesce(item->>'notes','');
    status_value := coalesce(item->>'status','New');
    follow_value := (item->>'follow_up_at')::timestamptz;

    if lead_id is null or length(name_value) not between 1 and 120 or length(phone_value)>40
      or phone_value !~ '^\+?[0-9 ()-]+$'
      or length(regexp_replace(phone_value,'[^0-9]','','g')) not between 7 and 15
      or length(institution_value)>200 or length(notes_value)>10000 then
      raise exception 'Enter a lead name, a valid phone number, and valid field lengths.';
    end if;

    if edit_existing and not exists(select 1 from public.contacts c where c.id=lead_id
      and c.created_by_employee=eid and c.assigned_employee_id=eid) then
      raise exception 'Only leads you added and still own can be edited here.';
    end if;
    if exists(select 1 from public.contacts c where c.assigned_employee_id=eid and c.id<>lead_id
      and public.employee_lead_phone_key(c.phone)=public.employee_lead_phone_key(phone_value)) then
      if edit_existing then raise exception 'You already have a lead with this phone number.'; end if;
      continue;
    end if;

    if edit_existing then
      update public.contacts set name=name_value,phone=phone_value,company=institution_value,
        institution=institution_value,notes=notes_value,status=status_value,follow_up_at=follow_value
      where id=lead_id and created_by_employee=eid and assigned_employee_id=eid;
      if not found then raise exception 'This lead is no longer assigned to you.'; end if;
      saved := saved + 1;
    else
      insert into public.contacts(id,name,phone,company,institution,notes,status,follow_up_at,
        assigned_employee_id,created_by_employee)
      values(lead_id,name_value,phone_value,institution_value,institution_value,notes_value,status_value,follow_value,eid,eid)
      on conflict(id) do nothing;
      if found then saved := saved + 1; end if;
    end if;
  end loop;
  return saved;
end $$;

revoke all on function public.employee_lead_phone_key(text),public.save_my_leads(jsonb) from public,anon;
grant execute on function public.save_my_leads(jsonb) to authenticated;

alter table public.call_records add column shared_review boolean not null default false;

-- Older Android builds upload cached calls as full rows. Preserve reviews saved through the RPC.
create function public.preserve_shared_call_review() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user='authenticated' then
    if tg_op='UPDATE' then
      new.shared_review := old.shared_review;
      if old.shared_review then
        new.outcome := old.outcome;
        new.notes := old.notes;
      end if;
    else
      new.shared_review := false;
    end if;
  end if;
  return new;
end $$;
create trigger preserve_shared_call_review before insert or update on public.call_records
  for each row execute function public.preserve_shared_call_review();

create function public.review_my_call(call_input text, outcome_input text, notes_input text,
  follow_up_input timestamptz default null) returns void
language plpgsql security definer set search_path='' as $$
declare
  eid uuid := public.employee_id();
  lead_id uuid;
begin
  if eid is null or outcome_input is null or outcome_input not in
    ('Not reviewed','Interested','Follow-up','No answer','Busy','Wrong number','Not interested','Converted')
    or notes_input is null or length(notes_input)>10000 then
    raise exception 'Enter a valid call outcome and notes.';
  end if;
  update public.call_records set outcome=outcome_input,notes=notes_input,shared_review=true
    where employee_id=eid and device_call_id=call_input returning contact_id into lead_id;
  if not found then raise exception 'This call is not in your workspace.'; end if;
  if outcome_input <> 'Not reviewed' then
    update public.contacts set status=case outcome_input
      when 'Converted' then 'Won' when 'Interested' then 'Interested'
      when 'Follow-up' then 'Follow-up' when 'Not interested' then 'Not interested'
      else 'Contacted' end,
      follow_up_at=case when outcome_input in ('Converted','Not interested') then null
        else coalesce(follow_up_input,follow_up_at) end
    where id=lead_id and assigned_employee_id=eid;
  end if;
end $$;
revoke all on function public.preserve_shared_call_review(),public.review_my_call(text,text,text,timestamptz)
  from public,anon;
grant execute on function public.review_my_call(text,text,text,timestamptz) to authenticated;
commit;
