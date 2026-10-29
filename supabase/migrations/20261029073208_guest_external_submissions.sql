-- External anonymous opening submissions: strictly isolated from authenticated opening records.
create table public.app_guest_submissions (
 id uuid primary key default gen_random_uuid(),
 client_id uuid not null unique,
 set_slug text not null references public.app_sets(slug),
 kind text not null check (kind in ('display','case','case_case')),
 label text not null default '',
 total_displays integer not null check (total_displays between 1 and 72),
 recorded_displays integer not null check(recorded_displays between 1 and total_displays),
 eligible_displays integer not null check(eligible_displays between 0 and recorded_displays),
 sections jsonb not null,
 hits jsonb not null,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 source text not null default 'external' check (source = 'external'),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz
);
create index app_guest_submissions_created on public.app_guest_submissions(created_at desc);
create index app_guest_submissions_status on public.app_guest_submissions(status);
alter table public.app_guest_submissions enable row level security;
revoke all on table public.app_guest_submissions from public, anon, authenticated;
grant select on public.app_guest_submissions to authenticated;
grant update(status,reviewed_at) on public.app_guest_submissions to authenticated;
create policy app_guest_submissions_approved_read on public.app_guest_submissions for select to authenticated
using ((select app_private.is_approved()) and (status='approved' or (select app_private.is_admin())));
create policy app_guest_submissions_admin_update on public.app_guest_submissions for update to authenticated
using ((select app_private.is_admin())) with check ((select app_private.is_admin()));

-- Restrict all state transitions to explicit admin approval/rejection.
create function app_private.review_guest_submission_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.id is distinct from old.id or new.client_id is distinct from old.client_id
  or new.set_slug is distinct from old.set_slug or new.kind is distinct from old.kind
  or new.label is distinct from old.label or new.total_displays is distinct from old.total_displays
  or new.recorded_displays is distinct from old.recorded_displays
  or new.eligible_displays is distinct from old.eligible_displays
  or new.sections is distinct from old.sections or new.hits is distinct from old.hits
  or new.source is distinct from old.source or new.created_at is distinct from old.created_at then
    raise exception 'Only review state may be changed';
 end if;
 if old.status <> 'pending' or new.status not in ('approved','rejected') then
   raise exception 'Only pending guest submissions can be reviewed';
 end if;
 new.reviewed_at=now();
 return new;
end; $$;
revoke all on function app_private.review_guest_submission_guard() from public,anon,authenticated;
create trigger app_guest_review_guard before update on public.app_guest_submissions
for each row execute function app_private.review_guest_submission_guard();

-- Public RPC validates every number and group membership on the server.
-- Guests cannot read/edit the table, create approved rows or alter signed-in user records.
create function public.app_submit_guest_opening(p_client_id uuid,p_payload jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare
  v_kind text;
  v_set text;
  v_label text;
  v_total integer;
  v_recorded integer := 0;
  v_eligible integer := 0;
  v_dpc integer;
  v_cpc integer;
  v_rules public.app_sets%rowtype;
  v_sections jsonb;
  v_section jsonb;
  v_ordinals jsonb;
  v_hits jsonb;
  v_sar integer;
  v_classics integer;
  v_ar integer;
  v_fur integer;
  v_rgb integer;
  v_opened integer;
  v_n integer;
  v_i integer;
  v_seen integer[] := '{}'::integer[];
  v_all jsonb := '{"sar":0,"classics":0,"ar":0,"fur":0,"rgb":0}'::jsonb;
  v_counts jsonb;
  v_number text;
  v_c text;
  v_value integer;
begin
 if p_client_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object'
    or octet_length(p_payload::text)>50000 then
   raise exception 'Invalid guest submission';
 end if;
 if exists(select 1 from public.app_guest_submissions where client_id=p_client_id) then
    raise exception 'This guest opening was already submitted';
 end if;
 if (select count(*) from public.app_guest_submissions
      where created_at>now()-interval '24 hours' and status='pending')>500 then
    raise exception 'Too many pending guest submissions; please try again later';
 end if;
 v_kind=p_payload->>'kind';
 v_set=p_payload->>'set_slug';
 v_label=left(coalesce(p_payload->>'label',''),120);
 select * into v_rules from public.app_sets where slug=v_set and active;
 if not found then raise exception 'Invalid set'; end if;
 if v_kind not in ('display','case','case_case') then raise exception 'Invalid package type'; end if;
 v_total=case v_kind when 'display' then 1 when 'case' then v_rules.displays_per_case
     else v_rules.displays_per_case*v_rules.cases_per_casecase end;
 if v_total>72 then raise exception 'Package too large for anonymous submission'; end if;
 v_sections=p_payload->'sections';
 if jsonb_typeof(v_sections)<>'array' or jsonb_array_length(v_sections) between 1 and 72 is not true then
   raise exception 'At least one complete section is required';
 end if;
 for v_section in select value from jsonb_array_elements(v_sections) loop
   if jsonb_typeof(v_section)<>'object' or (v_section->>'status')<>'closed' then
     raise exception 'Only manually closed sections can be submitted';
   end if;
   v_ordinals=v_section->'display_ordinals';
   if jsonb_typeof(v_ordinals)<>'array' then raise exception 'Invalid display selection'; end if;
   v_n=jsonb_array_length(v_ordinals);
   if v_n<1 or v_n>v_total or (v_section->>'mode') not in ('single','mixed')
      or ((v_section->>'mode')='single' and v_n<>1)
      or ((v_section->>'mode')='mixed' and v_n<2) then
       raise exception 'Invalid section size or mode';
   end if;
   for v_number in select value #>> '{}' from jsonb_array_elements(v_ordinals) loop
     if v_number !~ '^[0-9]{1,2}$' then raise exception 'Invalid display number'; end if;
     v_i=v_number::integer;
     if v_i<1 or v_i>v_total or v_i=any(v_seen) then
       raise exception 'Displays must be unique across sections';
     end if;
     v_seen=array_append(v_seen,v_i);
   end loop;
   v_recorded=v_recorded+v_n;
   if (v_section->>'opened_boosters') !~ '^[0-9]{1,4}$' then
     raise exception 'Invalid opened booster count';
   end if;
   v_opened=(v_section->>'opened_boosters')::integer;
   if v_opened>v_n*20 then raise exception 'Too many opened boosters'; end if;
   v_hits=v_section->'hits';
   if jsonb_typeof(v_hits)<>'object' then raise exception 'Invalid hits'; end if;
   v_counts='{}'::jsonb;
   foreach v_c in array array['sar','classics','ar','fur','rgb'] loop
      v_number=v_hits->>v_c;
      if v_number is null or v_number !~ '^[0-9]{1,9}$' then
         raise exception 'Invalid hit count for %',v_c;
      end if;
      v_value=v_number::integer;
      if (v_c='sar' and v_value>v_rules.sar_per_display*v_n)
         or (v_c='classics' and v_value>v_rules.classics_per_display*v_n)
         or (v_c='ar' and v_value>v_rules.ar_per_display*v_n) then
         raise exception 'Guaranteed hit count exceeds display limit';
      end if;
      v_counts=jsonb_set(v_counts,array[v_c],to_jsonb(v_value));
      v_all=jsonb_set(v_all,array[v_c],to_jsonb((v_all->>v_c)::integer+v_value));
   end loop;
   if (v_counts->>'sar')::integer=v_rules.sar_per_display*v_n
     and (v_counts->>'classics')::integer=v_rules.classics_per_display*v_n
     and (v_counts->>'ar')::integer=v_rules.ar_per_display*v_n then
      v_eligible=v_eligible+v_n;
   end if;
 end loop;
 if v_recorded>v_total then raise exception 'Too many displays'; end if;
 insert into public.app_guest_submissions(client_id,set_slug,kind,label,total_displays,
   recorded_displays,eligible_displays,sections,hits,status,source)
 values(p_client_id,v_set,v_kind,v_label,v_total,v_recorded,v_eligible,v_sections,
   v_all,'pending','external');
 return true;
end; $$;
revoke all on function public.app_submit_guest_opening(uuid,jsonb) from public,authenticated,anon;
grant execute on function public.app_submit_guest_opening(uuid,jsonb) to anon;
comment on table public.app_guest_submissions is 'Anonymous voluntary submissions; pending external data never silently counted as verified.';
