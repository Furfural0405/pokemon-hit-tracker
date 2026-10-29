create policy app_sets_guest_read on public.app_sets for select to anon using (active=true);
grant select (slug,title,displays_per_case,cases_per_casecase,sar_per_display,classics_per_display,ar_per_display,active) on public.app_sets to anon;
