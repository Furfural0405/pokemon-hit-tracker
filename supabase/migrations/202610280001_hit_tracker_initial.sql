-- Pokemon Hit Tracker - Initial schema (new, dedicated Supabase project only)
-- Apply only to a new project. Uses public schema with strict RLS.
create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

create table public.app_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('member','admin')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','suspended')),
  created_at timestamptz not null default now()
);

create function app_private.is_approved() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.app_profiles p where p.id = (select auth.uid()) and p.status = 'approved');
$$;
create function app_private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.app_profiles p where p.id = (select auth.uid()) and p.role = 'admin' and p.status = 'approved');
$$;
revoke all on function app_private.is_approved() from public;
revoke all on function app_private.is_admin() from public;
grant execute on function app_private.is_approved() to authenticated;
grant execute on function app_private.is_admin() to authenticated;

create function app_private.new_user_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.app_profiles(id, email) values(new.id, coalesce(new.email,''));
  return new;
end;
$$;
revoke all on function app_private.new_user_profile() from public;
create trigger on_hit_tracker_auth_user_created after insert on auth.users
for each row execute function app_private.new_user_profile();

create table public.app_sets (
  slug text primary key,
  title text not null,
  displays_per_case integer not null default 12 check(displays_per_case between 1 and 1000),
  cases_per_casecase integer not null default 6 check(cases_per_casecase between 1 and 100),
  sar_per_display integer not null default 1 check(sar_per_display >= 0),
  classics_per_display integer not null default 2 check(classics_per_display >= 0),
  ar_per_display integer not null default 4 check(ar_per_display >= 0),
  active boolean not null default true
);
insert into public.app_sets(slug,title,displays_per_case,cases_per_casecase,sar_per_display,classics_per_display,ar_per_display)
values('30th-sc','Pokémon 30. Jubiläum – Simplified Chinese',12,6,1,2,4);

create table public.app_openings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_profiles(id),
  set_slug text not null references public.app_sets(slug),
  kind text not null check (kind in ('display','case','case_case')),
  label text not null default '',
  -- Snapshot remains unchanged if future sets/rules are updated.
  rules jsonb not null default '{}'::jsonb,
  status text not null default 'active' check(status in ('active','closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create table public.app_displays (
  id uuid primary key default gen_random_uuid(),
  opening_id uuid not null references public.app_openings(id) on delete cascade,
  ordinal integer not null check(ordinal >= 1),
  case_no integer not null check(case_no >= 1),
  display_no integer not null check(display_no >= 1),
  unique(opening_id,ordinal), unique(opening_id,case_no,display_no)
);
create table public.app_groups (
  id uuid primary key default gen_random_uuid(),
  opening_id uuid not null references public.app_openings(id) on delete cascade,
  mode text not null check(mode in ('single','mixed')),
  status text not null default 'active' check(status in ('active','closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create unique index app_one_active_group_per_opening on public.app_groups(opening_id) where status='active';
create table public.app_group_displays (
  group_id uuid not null references public.app_groups(id) on delete cascade,
  display_id uuid not null unique references public.app_displays(id) on delete cascade,
  primary key(group_id,display_id)
);
create table public.app_hit_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.app_groups(id) on delete cascade,
  category text not null check(category in ('sar','classics','ar','fur','rgb')),
  created_at timestamptz not null default now()
);
create index app_openings_owner_created on public.app_openings(user_id,created_at desc);
create index app_displays_opening on public.app_displays(opening_id);
create index app_groups_opening on public.app_groups(opening_id);
create index app_events_group_category on public.app_hit_events(group_id,category);

-- Prevent rules or user ownership being overridden even by direct client inserts.
create function app_private.prepare_opening() returns trigger
language plpgsql set search_path = '' as $$
declare r public.app_sets%rowtype;
begin
 select * into r from public.app_sets where slug=new.set_slug and active;
 if not found then raise exception 'Unknown or inactive set'; end if;
 if new.user_id <> (select auth.uid()) then raise exception 'Invalid owner'; end if;
 new.rules=jsonb_build_object('displays_per_case',r.displays_per_case,
  'cases_per_casecase',r.cases_per_casecase,'sar',r.sar_per_display,
  'classics',r.classics_per_display,'ar',r.ar_per_display);
 new.status='active'; new.closed_at=null;
 return new;
end; $$;
create trigger app_prepare_opening before insert on public.app_openings
for each row execute function app_private.prepare_opening();

create function app_private.validate_display() returns trigger
language plpgsql set search_path = '' as $$
declare o public.app_openings%rowtype; dpc integer; total integer;
begin
 select * into o from public.app_openings where id=new.opening_id;
 if not found or o.status<>'active' then raise exception 'Opening unavailable'; end if;
 dpc=(o.rules->>'displays_per_case')::integer;
 total=case when o.kind='display' then 1 when o.kind='case' then dpc else dpc*(o.rules->>'cases_per_casecase')::integer end;
 if new.ordinal<1 or new.ordinal>total or new.case_no<>((new.ordinal-1)/dpc)+1
  or new.display_no<>((new.ordinal-1)%dpc)+1 then
   raise exception 'Invalid display position';
 end if;
 return new;
end; $$;
create trigger app_validate_display before insert on public.app_displays
for each row execute function app_private.validate_display();

create function app_private.validate_membership() returns trigger
language plpgsql set search_path = '' as $$
declare group_opening uuid; display_opening uuid; g_mode text; g_status text; n integer;
begin
 select opening_id,mode,status into group_opening,g_mode,g_status
 from public.app_groups where id=new.group_id for update;
 select opening_id into display_opening from public.app_displays where id=new.display_id;
 if group_opening is null or display_opening is distinct from group_opening then
   raise exception 'Display and group must belong to the same opening';
 end if;
 if g_status <> 'active' then raise exception 'Group already closed'; end if;
 if exists(select 1 from public.app_hit_events where group_id=new.group_id) then raise exception 'Group membership frozen after first hit'; end if;
 if g_mode='single' then
   select count(*) into n from public.app_group_displays where group_id=new.group_id;
   if n>0 then raise exception 'Single group must contain exactly one display'; end if;
 end if;
 return new;
end; $$;
create trigger app_validate_membership before insert on public.app_group_displays
for each row execute function app_private.validate_membership();

create function app_private.validate_hit_event() returns trigger
language plpgsql set search_path = '' as $$
declare active_group text; opening_status text; grp_opening uuid; n integer; expected integer; actual integer;
begin
 -- Serializes hit updates for the same group so limits cannot be raced.
 select status,opening_id into active_group,grp_opening from public.app_groups where id=new.group_id for update;
 select status into opening_status from public.app_openings where id=grp_opening;
 if active_group <> 'active' or opening_status <> 'active' then
   raise exception 'Opening section is closed';
 end if;
 if new.category in ('sar','classics','ar') then
   select count(*) into n from public.app_group_displays where group_id=new.group_id;
   if n=0 then raise exception 'Group has no displays'; end if;
   select (o.rules ->> new.category)::integer * n into expected
   from public.app_openings o where o.id=grp_opening;
   select count(*) into actual from public.app_hit_events
   where group_id=new.group_id and category=new.category;
   if actual >= expected then raise exception 'Guaranteed hit limit reached'; end if;
 end if;
 return new;
end; $$;
create trigger app_validate_hit_event before insert on public.app_hit_events
for each row execute function app_private.validate_hit_event();

create function app_private.validate_hit_delete() returns trigger
language plpgsql set search_path = '' as $$
declare gs text; os text;
begin
 select g.status,o.status into gs,os from public.app_groups g
 join public.app_openings o on o.id=g.opening_id where g.id=old.group_id for update of g;
 if gs <> 'active' or os <> 'active' then raise exception 'Opening section is closed'; end if;
 return old;
end; $$;
create trigger app_validate_hit_delete before delete on public.app_hit_events
for each row execute function app_private.validate_hit_delete();

create function app_private.validate_group_close() returns trigger
language plpgsql set search_path = '' as $$
declare os text;
begin
 if old.status <> 'active' or new.status <> 'closed' then raise exception 'Closed sections cannot be reopened'; end if;
 select status into os from public.app_openings where id=old.opening_id;
 if os <> 'active' then raise exception 'Opening is closed'; end if;
 if (select count(*) from public.app_group_displays where group_id=old.id) < (case when old.mode='mixed' then 2 else 1 end) then raise exception 'Not enough displays in opening section'; end if;
 new.closed_at=now();
 return new;
end; $$;
create trigger app_validate_group_close before update on public.app_groups
for each row execute function app_private.validate_group_close();

create function app_private.validate_opening_close() returns trigger
language plpgsql set search_path = '' as $$
begin
 if old.status <> 'active' or new.status <> 'closed' then raise exception 'Closed openings cannot be reopened'; end if;
 if exists(select 1 from public.app_groups where opening_id=old.id and status='active') then
  raise exception 'Close active section first';
 end if;
 new.closed_at=now();
 return new;
end; $$;
create trigger app_validate_opening_close before update on public.app_openings
for each row execute function app_private.validate_opening_close();

-- Atomic creation of a case/display hierarchy from immutable set rules.
create function public.app_create_opening(p_set_slug text,p_kind text,p_label text default '')
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid; v_dpc integer; v_cpc integer; v_total integer; i integer;
begin
 if not app_private.is_approved() then raise exception 'Account not approved'; end if;
 if p_kind not in ('display','case','case_case') then raise exception 'Invalid package type'; end if;
 select displays_per_case,cases_per_casecase into v_dpc,v_cpc
 from public.app_sets where slug=p_set_slug and active;
 if not found then raise exception 'Unknown set'; end if;
 v_total:=case when p_kind='display' then 1 when p_kind='case' then v_dpc else v_dpc*v_cpc end;
 insert into public.app_openings(user_id,set_slug,kind,label)
 values((select auth.uid()),p_set_slug,p_kind,left(coalesce(p_label,''),120)) returning id into v_id;
 for i in 1..v_total loop
  insert into public.app_displays(opening_id,ordinal,case_no,display_no)
  values(v_id,i, ((i-1)/v_dpc)+1, ((i-1)%v_dpc)+1);
 end loop;
 return v_id;
end; $$;

-- Atomic assignment of *previously unassigned*, completely unopened displays.
create function public.app_start_group(p_opening_id uuid,p_mode text,p_display_ids uuid[])
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid; n integer; assigned integer; opening_status text;
begin
 if not app_private.is_approved() then raise exception 'Account not approved'; end if;
 select status into opening_status from public.app_openings
 where id=p_opening_id and user_id=(select auth.uid()) for update;
 if opening_status is distinct from 'active' then raise exception 'Opening unavailable'; end if;
 if p_mode not in ('single','mixed') then raise exception 'Invalid method'; end if;
 n=coalesce(array_length(p_display_ids,1),0);
 if n=0 or n>1000 or (p_mode='single' and n<>1) or (p_mode='mixed' and n<2) then
  raise exception 'Invalid number of displays';
 end if;
 if (select count(distinct x) from unnest(p_display_ids) x)<>n then
   raise exception 'Duplicate display in selection';
 end if;
 -- Lock all selected display rows. Opening row lock serializes group starts.
 select count(*) into assigned from public.app_displays d
 where d.opening_id=p_opening_id and d.id=any(p_display_ids)
 and not exists(select 1 from public.app_group_displays gd where gd.display_id=d.id);
 if assigned<>n then raise exception 'Display unavailable or already opened'; end if;
 insert into public.app_groups(opening_id,mode) values(p_opening_id,p_mode) returning id into v_id;
 insert into public.app_group_displays(group_id,display_id)
 select v_id,d.id from public.app_displays d where d.opening_id=p_opening_id and d.id=any(p_display_ids);
 return v_id;
end; $$;
revoke all on function public.app_create_opening(text,text,text) from public,anon;
revoke all on function public.app_start_group(uuid,text,uuid[]) from public,anon;
grant execute on function public.app_create_opening(text,text,text) to authenticated;
grant execute on function public.app_start_group(uuid,text,uuid[]) to authenticated;

-- RLS in every public table.
alter table public.app_profiles enable row level security;
alter table public.app_sets enable row level security;
alter table public.app_openings enable row level security;
alter table public.app_displays enable row level security;
alter table public.app_groups enable row level security;
alter table public.app_group_displays enable row level security;
alter table public.app_hit_events enable row level security;

create policy app_profiles_select on public.app_profiles for select to authenticated
using (id=(select auth.uid()) or (select app_private.is_admin()));
create policy app_profiles_admin_update on public.app_profiles for update to authenticated
using ((select app_private.is_admin())) with check ((select app_private.is_admin()));

create policy app_sets_select on public.app_sets for select to authenticated
using ((select app_private.is_approved()));
create policy app_openings_select on public.app_openings for select to authenticated
using (user_id=(select auth.uid()) and (select app_private.is_approved()));
create policy app_openings_insert on public.app_openings for insert to authenticated
with check (user_id=(select auth.uid()) and (select app_private.is_approved()));
create policy app_openings_update on public.app_openings for update to authenticated
using (user_id=(select auth.uid()) and (select app_private.is_approved()))
with check (user_id=(select auth.uid()) and (select app_private.is_approved()));

create policy app_displays_select on public.app_displays for select to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid())));
create policy app_displays_insert on public.app_displays for insert to authenticated
with check ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid()) and o.status='active'));

create policy app_groups_select on public.app_groups for select to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid())));
create policy app_groups_insert on public.app_groups for insert to authenticated
with check ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid()) and o.status='active'));
create policy app_groups_update on public.app_groups for update to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid()) and o.status='active'))
with check ((select app_private.is_approved()) and exists(select 1 from public.app_openings o where o.id=opening_id and o.user_id=(select auth.uid())));

create policy app_group_displays_select on public.app_group_displays for select to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_groups g join public.app_openings o on o.id=g.opening_id
 where g.id=group_id and o.user_id=(select auth.uid())));
create policy app_group_displays_insert on public.app_group_displays for insert to authenticated
with check ((select app_private.is_approved()) and exists(select 1 from public.app_groups g join public.app_openings o on o.id=g.opening_id
 where g.id=group_id and o.user_id=(select auth.uid()) and o.status='active'));

create policy app_hit_events_select on public.app_hit_events for select to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_groups g join public.app_openings o on o.id=g.opening_id
 where g.id=group_id and o.user_id=(select auth.uid())));
create policy app_hit_events_insert on public.app_hit_events for insert to authenticated
with check ((select app_private.is_approved()) and exists(select 1 from public.app_groups g join public.app_openings o on o.id=g.opening_id
 where g.id=group_id and o.user_id=(select auth.uid()) and o.status='active'));
create policy app_hit_events_delete on public.app_hit_events for delete to authenticated
using ((select app_private.is_approved()) and exists(select 1 from public.app_groups g join public.app_openings o on o.id=g.opening_id
 where g.id=group_id and o.user_id=(select auth.uid()) and o.status='active'));

-- Limit table access to the exact operations required by the client.
revoke all on public.app_profiles, public.app_sets, public.app_openings, public.app_displays,
 public.app_groups, public.app_group_displays, public.app_hit_events from anon,authenticated;
grant select on public.app_profiles, public.app_sets, public.app_openings, public.app_displays,
 public.app_groups, public.app_group_displays, public.app_hit_events to authenticated;
grant update(status,role) on public.app_profiles to authenticated;
grant insert on public.app_openings,public.app_displays,public.app_groups,
 public.app_group_displays,public.app_hit_events to authenticated;
grant update(status) on public.app_openings,public.app_groups to authenticated;
grant delete on public.app_hit_events to authenticated;

comment on table public.app_profiles is 'Pending users must be manually approved by an admin; RLS protects access.';
comment on table public.app_hit_events is 'One row per drawn card; deletion from active section records a correction.';