-- Enable live expert-case and message events. Row Level Security still controls
-- which changes each authenticated client can receive.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'expert_cases'
  ) then
    alter publication supabase_realtime add table public.expert_cases;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'case_messages'
  ) then
    alter publication supabase_realtime add table public.case_messages;
  end if;
end
$$;
