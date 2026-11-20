-- Track each email recipient so a partial SMTP response can never mark all recipients sent.
begin;
create table public.notification_delivery_recipients(id uuid primary key default gen_random_uuid(),delivery_id uuid not null references public.notification_deliveries(id) on delete cascade,email text not null,status text not null default 'pending' check(status in ('pending','retry','sent','failed')),attempts integer not null default 0,provider_id text,last_error text,sent_at timestamptz,created_at timestamptz not null default now(),unique(delivery_id,email));
create index notification_delivery_recipient_pending on public.notification_delivery_recipients(delivery_id,status);
alter table public.notification_delivery_recipients enable row level security;
create policy delivery_recipient_manage on public.notification_delivery_recipients for select to authenticated using(public.has_permission('notifications.manage'));
grant select on public.notification_delivery_recipients to authenticated;grant all on public.notification_delivery_recipients to service_role;
-- Final-attempt leases are terminalized before claiming new work; they cannot remain permanently processing.
create or replace function public.claim_notification_deliveries(batch_size integer default 30) returns setof public.notification_deliveries language plpgsql security definer set search_path='' as $$begin
 update public.notification_deliveries d set status='failed',locked_at=null,last_error=coalesce(last_error,'Delivery worker lease expired after the final retry.') where d.status='processing' and d.attempts>=8 and d.locked_at<now()-interval '5 minutes';
 return query update public.notification_deliveries d set status='processing',locked_at=now(),attempts=attempts+1 where d.id in(select x.id from public.notification_deliveries x join public.notifications n on n.id=x.notification_id where ((x.status in('pending','retry') and x.available_at<=now()) or (x.status='processing' and x.locked_at<now()-interval '5 minutes' and x.attempts<8)) and n.available_at<=now() and n.cancelled_at is null and x.attempts<8 order by x.available_at,x.created_at for update of x skip locked limit greatest(1,least(coalesce(batch_size,30),100))) returning d.*;
end$$;
create or replace function public.retry_notification_deliveries() returns integer language plpgsql security definer set search_path='' as $$declare total integer;begin
 if not public.has_permission('notifications.manage') then raise exception 'Notification permission required.';end if;
 update public.notification_deliveries d set status='pending',attempts=0,available_at=now(),last_error=null,locked_at=null where (d.status in('blocked','failed','skipped') or (d.status='processing' and d.locked_at<now()-interval '5 minutes')) and exists(select 1 from public.notifications n where n.id=d.notification_id and n.cancelled_at is null and n.available_at<=now());
 update public.notification_delivery_recipients set status='pending',attempts=0,last_error=null where status='failed';get diagnostics total=row_count;return total;
end$$;
insert into public.schema_migrations(version) values('20261118_009_delivery_reliability');
commit;
