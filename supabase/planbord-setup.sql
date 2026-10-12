-- Planbord: database voor inloggen en synchroniseren.
-- Plak dit hele script in Supabase > SQL Editor > New query en klik op Run.
-- Je kunt het veilig vaker uitvoeren.

-- 1. Eén rij per persoon met al zijn of haar borden
create table if not exists public.planbord (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  state jsonb not null,
  updated_at timestamptz not null default now()
);

grant select, insert, update, delete on public.planbord to authenticated;

-- Ieder ziet en wijzigt alleen de eigen borden (Row Level Security)
alter table public.planbord enable row level security;

drop policy if exists "Eigen borden lezen" on public.planbord;
drop policy if exists "Eigen borden toevoegen" on public.planbord;
drop policy if exists "Eigen borden wijzigen" on public.planbord;
drop policy if exists "Eigen borden verwijderen" on public.planbord;
create policy "Eigen borden lezen" on public.planbord for select to authenticated using ((select auth.uid()) = user_id);
create policy "Eigen borden toevoegen" on public.planbord for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Eigen borden wijzigen" on public.planbord for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Eigen borden verwijderen" on public.planbord for delete to authenticated using ((select auth.uid()) = user_id);

-- Tijdstip van de laatste wijziging zet de database zelf
create or replace function public.planbord_bijgewerkt() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;
drop trigger if exists planbord_bijgewerkt on public.planbord;
create trigger planbord_bijgewerkt before insert or update on public.planbord
  for each row execute function public.planbord_bijgewerkt();

-- 2. Opslag voor bijlagen (mails en bestanden), per persoon een eigen map
insert into storage.buckets (id, name, public) values ('bijlagen', 'bijlagen', false)
on conflict (id) do nothing;

drop policy if exists "Eigen bijlagen lezen" on storage.objects;
drop policy if exists "Eigen bijlagen toevoegen" on storage.objects;
drop policy if exists "Eigen bijlagen wijzigen" on storage.objects;
drop policy if exists "Eigen bijlagen verwijderen" on storage.objects;
create policy "Eigen bijlagen lezen" on storage.objects for select to authenticated
  using (bucket_id = 'bijlagen' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Eigen bijlagen toevoegen" on storage.objects for insert to authenticated
  with check (bucket_id = 'bijlagen' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Eigen bijlagen wijzigen" on storage.objects for update to authenticated
  using (bucket_id = 'bijlagen' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Eigen bijlagen verwijderen" on storage.objects for delete to authenticated
  using (bucket_id = 'bijlagen' and (storage.foldername(name))[1] = (select auth.uid())::text);
