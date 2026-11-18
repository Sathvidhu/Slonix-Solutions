begin;
-- Older Android clients serialize local IST timestamps without an offset.
create function public.break_timestamp(value_input text) returns timestamptz language sql stable set search_path='' as $$select case when value_input is null then null when value_input ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then value_input::timestamptz else value_input::timestamp at time zone 'Asia/Kolkata' end$$;
create function public.normalize_break_json(value_input jsonb) returns jsonb language plpgsql stable set search_path='' as $$declare result jsonb:='[]';item jsonb;k text;begin
 for item in select value from jsonb_array_elements(value_input) loop
 foreach k in array array['start','end','deadline'] loop if item->>k is not null then item:=jsonb_set(item,array[k],to_jsonb(public.break_timestamp(item->>k)));end if;end loop;
 result:=result||jsonb_build_array(item);end loop;return result;end$$;
create function public.normalize_shift_breaks() returns trigger language plpgsql set search_path='' as $$begin new.breaks:=public.normalize_break_json(new.breaks);return new;end$$;
create trigger montme_normalize_breaks before insert or update of breaks on public.shift_records for each row execute function public.normalize_shift_breaks();
update public.break_records b set started_at=public.break_timestamp(s.breaks->b.break_index->>'start'),ended_at=public.break_timestamp(s.breaks->b.break_index->>'end'),deadline_at=public.break_deadline(public.break_timestamp(s.breaks->b.break_index->>'start'),b.kind) from public.shift_records s where s.id=b.shift_id;
update public.shift_records set breaks=public.normalize_break_json(breaks) where breaks<>public.normalize_break_json(breaks);
update public.activity_events a set occurred_at=b.started_at from public.break_records b where a.event_key='break-start:'||b.shift_id||':'||b.break_index;
update public.activity_events a set occurred_at=b.ended_at from public.break_records b where b.ended_at is not null and a.event_key='break-end:'||b.shift_id||':'||b.break_index;
update public.notifications n set available_at=b.deadline_at,cancelled_at=case when b.ended_at is not null and b.ended_at<=b.deadline_at then coalesce(n.cancelled_at,now()) else n.cancelled_at end from public.break_records b where n.event_key in('break-reminder:'||b.shift_id||':'||b.break_index,'admin-break-reminder:'||b.shift_id||':'||b.break_index);
update public.notification_deliveries d set available_at=n.available_at,status=case when n.cancelled_at is not null then 'cancelled' else d.status end from public.notifications n where d.notification_id=n.id and n.kind='break_reminder' and d.status in('pending','retry','blocked');
revoke all on function public.break_timestamp(text),public.normalize_break_json(jsonb),public.normalize_shift_breaks() from public,anon;
grant execute on function public.break_timestamp(text),public.normalize_break_json(jsonb),public.normalize_shift_breaks() to authenticated;
commit;
