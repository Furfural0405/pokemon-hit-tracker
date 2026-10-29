-- Opt-in public live opening feed. No emails, owner IDs or private history are exposed.
alter table public.app_openings add column is_live_public boolean not null default false;
alter table public.app_groups add column opened_boosters integer not null default 0 check(opened_boosters >= 0);

create table public.app_live_feed (
 opening_id uuid primary key references public.app_openings(id) on delete cascade,
 public_id uuid not null default gen_random_uuid() unique,
 snapshot jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now()
);
alter table public.app_live_feed enable row level security;
revoke all on public.app_live_feed from public, anon, authenticated;
grant select on public.app_live_feed to anon, authenticated;
create policy app_live_feed_public_read on public.app_live_feed
 for select to anon, authenticated using (true);

grant update(is_live_public) on public.app_openings to authenticated;
grant update(opened_boosters) on public.app_groups to authenticated;
grant delete on public.app_openings to authenticated;
create policy app_openings_delete on public.app_openings for delete to authenticated
using (user_id=(select auth.uid()) and (select app_private.is_approved()));

-- Preserve the existing manual-close rules while permitting visibility-only updates.
create or replace function app_private.validate_opening_close() returns trigger
language plpgsql set search_path = '' as $$
begin
 if old.status='active' and new.status='closed' then
   if exists(select 1 from public.app_groups where opening_id=old.id and status='active') then
     raise exception 'Close active section first';
   end if;
   new.closed_at=now();
   new.is_live_public=false;
 elsif old.status='active' and new.status='active'
   and new.is_live_public is distinct from old.is_live_public then
   null;
 else
   raise exception 'Only visibility changes or manual closing are allowed';
 end if;
 return new;
end; $$;

-- A section may update its booster count without being closed.
create or replace function app_private.validate_group_close() returns trigger
language plpgsql set search_path = '' as $$
declare os text; n integer;
begin
 if old.status <> 'active' or new.status not in ('active','closed') then
   raise exception 'Closed sections cannot be changed';
 end if;
 select status into os from public.app_openings where id=old.opening_id;
 if os <> 'active' then raise exception 'Opening is closed'; end if;
 select count(*) into n from public.app_group_displays where group_id=old.id;
 if new.opened_boosters > n * 20 then
    raise exception 'Opened boosters exceed pool size';
 end if;
 if new.status='closed' then
   if n < (case when old.mode='mixed' then 2 else 1 end) then
     raise exception 'Not enough displays in opening section';
   end if;
   new.closed_at=now();
 elsif new.opened_boosters is not distinct from old.opened_boosters then
   raise exception 'No booster progress change';
 end if;
 return new;
end; $$;

-- When an owner deletes an entire opening, cascaded hit rows may be removed
-- even after the section was closed. Direct hit edits remain protected.
create or replace function app_private.validate_hit_delete() returns trigger
language plpgsql set search_path = '' as $$
declare gs text; os text;
begin
 if pg_trigger_depth() > 1 then return old; end if;
 select g.status,o.status into gs,os from public.app_groups g
 join public.app_openings o on o.id=g.opening_id where g.id=old.group_id for update of g;
 if gs <> 'active' or os <> 'active' then raise exception 'Opening section is closed'; end if;
 return old;
end; $$;

-- Only the trusted trigger assembles the public projection; clients can SELECT only.
create function app_private.sync_live_feed(p_opening_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  o public.app_openings%rowtype;
  g public.app_groups%rowtype;
  v_group jsonb := null;
  v_counts jsonb;
  v_total jsonb;
  n integer;
begin
  if p_opening_id is null then return; end if;
  select * into o from public.app_openings where id=p_opening_id;
  if not found or o.status <> 'active' or not o.is_live_public then
    delete from public.app_live_feed where opening_id=p_opening_id;
    return;
  end if;
  select * into g from public.app_groups
   where opening_id=p_opening_id and status='active' order by created_at desc limit 1;
  if found then
    select count(*)::integer into n from public.app_group_displays where group_id=g.id;
    select jsonb_build_object(
      'sar',count(*) filter(where category='sar'),
      'classics',count(*) filter(where category='classics'),
      'ar',count(*) filter(where category='ar'),
      'fur',count(*) filter(where category='fur'),
      'rgb',count(*) filter(where category='rgb')
    ) into v_counts from public.app_hit_events where group_id=g.id;
    v_group=jsonb_build_object(
      'mode',g.mode,
      'displays',n,
      'opened_boosters',g.opened_boosters,
      'total_boosters',n*20,
      'hits',v_counts,
      'targets',jsonb_build_object(
        'sar',coalesce((o.rules->>'sar')::integer,0)*n,
        'classics',coalesce((o.rules->>'classics')::integer,0)*n,
        'ar',coalesce((o.rules->>'ar')::integer,0)*n
      )
    );
  end if;
  select jsonb_build_object(
    'sar',count(*) filter(where h.category='sar'),
    'classics',count(*) filter(where h.category='classics'),
    'ar',count(*) filter(where h.category='ar'),
    'fur',count(*) filter(where h.category='fur'),
    'rgb',count(*) filter(where h.category='rgb')
  ) into v_total from public.app_hit_events h
  join public.app_groups gr on gr.id=h.group_id where gr.opening_id=p_opening_id;
  insert into public.app_live_feed(opening_id,snapshot,updated_at)
  values(p_opening_id,jsonb_build_object(
    'label',coalesce(nullif(o.label,''),'Laufende Öffnung'),
    'kind',o.kind,
    'set_slug',o.set_slug,
    'total_displays',(case o.kind when 'display' then 1
      when 'case' then (o.rules->>'displays_per_case')::integer
      else (o.rules->>'displays_per_case')::integer*(o.rules->>'cases_per_casecase')::integer end),
    'active_group',v_group,
    'total_hits',v_total
  ),now())
  on conflict(opening_id) do update
    set snapshot=excluded.snapshot,updated_at=excluded.updated_at;
end;
$$;
revoke all on function app_private.sync_live_feed(uuid) from public, anon, authenticated;

create function app_private.refresh_live_feed_trigger() returns trigger
language plpgsql security definer set search_path = '' as $$
declare oid uuid;
begin
 if tg_table_name='app_openings' then
   oid=coalesce(new.id,old.id);
 elsif tg_table_name='app_groups' then
   oid=coalesce(new.opening_id,old.opening_id);
 elsif tg_table_name='app_group_displays' then
   select opening_id into oid from public.app_groups
     where id=coalesce(new.group_id,old.group_id);
 elsif tg_table_name='app_hit_events' then
   select g.opening_id into oid from public.app_groups g
     where g.id=coalesce(new.group_id,old.group_id);
 end if;
 perform app_private.sync_live_feed(oid);
 return coalesce(new,old);
end; $$;
revoke all on function app_private.refresh_live_feed_trigger() from public, anon, authenticated;

create trigger app_live_opening_refresh after update of status,is_live_public on public.app_openings
 for each row execute function app_private.refresh_live_feed_trigger();
create trigger app_live_group_refresh after insert or update or delete on public.app_groups
 for each row execute function app_private.refresh_live_feed_trigger();
create trigger app_live_membership_refresh after insert or delete on public.app_group_displays
 for each row execute function app_private.refresh_live_feed_trigger();
create trigger app_live_hits_refresh after insert or delete on public.app_hit_events
 for each row execute function app_private.refresh_live_feed_trigger();

do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
   and schemaname='public' and tablename='app_live_feed') then
    alter publication supabase_realtime add table public.app_live_feed;
 end if;
end $$;
comment on table public.app_live_feed is 'Sanitized, opt-in, public read-only live counters. Never stores email or private profiles.';
