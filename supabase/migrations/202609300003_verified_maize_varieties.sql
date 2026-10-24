-- Verified Philippine starter catalog; retain retired records for review history.
begin;
alter table public.maize_varieties add column if not exists active boolean not null default true;
alter table public.maize_varieties add column if not exists source_url text;
alter table public.maize_varieties add column if not exists verification_note text;
update public.maize_varieties set active=false,verification_note='Retired: exact Philippine variety could not be verified, or entry is a broad category.'
 where normalized_name in ('dekalbdk8888s','dekalb8888s','nativetraditionalwhitecorn','pioneerp3530');
insert into public.maize_varieties(name,active,source_url,verification_note) values
('Pioneer P3530YHR',true,'https://www.corteva.com/ph/mga-produkto-at-solusyon/seeds/p3530yhr.html','Listed by Corteva Philippines.'),
('Pioneer 30T80',true,'https://www.frontiersin.org/journals/microbiology/articles/10.3389/fmicb.2018.01295/full','Historical Philippine research use; current seed availability is not confirmed.'),
('Dekalb DK 8131S',true,'https://www.da.gov.ph/wp-content/uploads/2022/02/ao07_s2022.pdf','Documented in the Philippine DA/NSIC registration list.'),
('NK 6410',true,'https://www.syngenta.com.ph/product/seed/corn/nk6410','Listed by Syngenta Philippines.'),
('NK 8840',true,'https://www.syngenta.com.ph/tl/corn','Listed by Syngenta Philippines.'),
('IPB Var 6',true,'https://pejard.slu.edu.ph/vol.12/2022.05.23.pdf','Documented in Philippine field research.')
on conflict(normalized_name) do update set active=true,source_url=excluded.source_url,verification_note=excluded.verification_note;
insert into public.maize_variety_aliases(normalized_name,variety_id)
 select 'pioneerp3530',id from public.maize_varieties where normalized_name='pioneerp3530yhr'
 on conflict(normalized_name) do update set variety_id=excluded.variety_id;
-- Old entries remain hidden from dropdowns and merge choices. Submitted field
-- descriptions and past review references remain intact.
create or replace function public.suggest_maize_variety(p_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_key text := public.normalize_maize_variety(p_name); v_id uuid; v_name text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if char_length(trim(p_name)) not between 2 and 120 or v_key='' then raise exception 'Enter a valid variety name (2–120 characters)'; end if;
 if v_key in ('pioneer','dekalb','nk','bioseed') then raise exception 'Enter a specific hybrid or variety, not only a brand'; end if;
 perform pg_advisory_xact_lock(hashtextextended('maize-catalog',0));
 select id,name into v_id,v_name from public.maize_varieties where normalized_name=v_key and active;
 if v_id is null then
  select v.id,v.name into v_id,v_name from public.maize_variety_aliases a join public.maize_varieties v on v.id=a.variety_id where a.normalized_name=v_key and v.active;
 end if;
 if v_id is not null then return jsonb_build_object('status','existing','name',v_name); end if;
 if not exists(select 1 from public.maize_variety_suggestions where normalized_name=v_key and status='pending') then
  if (select count(*) from public.maize_variety_suggestions where owner_id=auth.uid() and created_at>now()-interval '1 day') >=20 then raise exception 'Daily suggestion limit reached'; end if;
  insert into public.maize_variety_suggestions(owner_id,name) values(auth.uid(),trim(p_name));
 end if;
 return jsonb_build_object('status','pending','name',trim(p_name));
end; $$;

notify pgrst,'reload schema';
commit;
