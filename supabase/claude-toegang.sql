-- Planbord: Claude kaarten laten toevoegen, afvinken en archiveren.
-- Voer dit één keer uit in Supabase > SQL Editor, na planbord-setup.sql. Je kunt het veilig vaker uitvoeren.
--
-- Hoe het werkt:
-- - In de app maak je (Account > Sleutel voor Claude maken) een geheime sleutel. De database bewaart alleen een hash ervan.
-- - Claude stuurt met die sleutel opdrachten ("zet deze kaart in Vandaag", "archiveer kaart X") naar de tabel planbord_opdrachten.
-- - Claude past je borden zelf nooit aan. De app op je apparaat haalt de opdrachten op, voert ze uit als gewone wijziging
--   en synchroniseert zoals altijd. Zo raakt niets kwijt van wat je zelf net hebt aangepast.
-- - Een nieuwe sleutel maken of op "Claude-toegang intrekken" klikken maakt de oude sleutel meteen ongeldig.

-- 1. Sleutel per persoon (alleen de hash)
create table if not exists public.planbord_claude (
  user_id uuid primary key references auth.users (id) on delete cascade,
  sleutel_hash text not null unique,
  aangemaakt timestamptz not null default now()
);
alter table public.planbord_claude enable row level security;
revoke all on public.planbord_claude from anon, authenticated;

-- 2. Opdrachten die nog door de app uitgevoerd moeten worden
create table if not exists public.planbord_opdrachten (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  opdracht jsonb not null,
  aangemaakt timestamptz not null default now()
);
create index if not exists planbord_opdrachten_user on public.planbord_opdrachten (user_id, id);
alter table public.planbord_opdrachten enable row level security;
revoke all on public.planbord_opdrachten from anon, authenticated;
grant select, delete on public.planbord_opdrachten to authenticated;
drop policy if exists "Eigen opdrachten lezen" on public.planbord_opdrachten;
drop policy if exists "Eigen opdrachten verwijderen" on public.planbord_opdrachten;
create policy "Eigen opdrachten lezen" on public.planbord_opdrachten for select to authenticated using ((select auth.uid()) = user_id);
create policy "Eigen opdrachten verwijderen" on public.planbord_opdrachten for delete to authenticated using ((select auth.uid()) = user_id);

-- 3. Functies voor de ingelogde persoon in de app: sleutel maken en intrekken
create or replace function public.claude_sleutel_maken() returns text
language plpgsql security definer set search_path = '' as $$
declare s text := 'pb_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  if auth.uid() is null then raise exception 'Niet ingelogd'; end if;
  insert into public.planbord_claude (user_id, sleutel_hash) values (auth.uid(), encode(sha256(convert_to(s, 'UTF8')), 'hex'))
  on conflict (user_id) do update set sleutel_hash = excluded.sleutel_hash, aangemaakt = now();
  return s;
end $$;

create or replace function public.claude_sleutel_intrekken() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.planbord_claude where user_id = auth.uid();
  delete from public.planbord_opdrachten where user_id = auth.uid();
end $$;

create or replace function public.claude_toegang_aan() returns boolean
language sql security definer set search_path = '' stable as $$
  select exists (select 1 from public.planbord_claude where user_id = auth.uid());
$$;

-- 4. Functies voor Claude, alleen bruikbaar met de juiste sleutel
create or replace function public.claude_gebruiker(sleutel text) returns uuid
language plpgsql security definer set search_path = '' stable as $$
declare u uuid;
begin
  select user_id into u from public.planbord_claude where sleutel_hash = encode(sha256(convert_to(coalesce(sleutel, ''), 'UTF8')), 'hex');
  if u is null then raise exception 'Ongeldige sleutel' using errcode = '28000'; end if;
  return u;
end $$;

-- Borden lezen (zoals ze het laatst gesynchroniseerd zijn) en de opdrachten die nog wachten
create or replace function public.claude_borden(sleutel text) returns jsonb
language plpgsql security definer set search_path = '' stable as $$
declare u uuid := public.claude_gebruiker(sleutel);
begin
  return jsonb_build_object(
    'state', (select state from public.planbord where user_id = u),
    'bijgewerkt', (select updated_at from public.planbord where user_id = u),
    'wachtend', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'opdracht', opdracht, 'aangemaakt', aangemaakt) order by id)
                          from public.planbord_opdrachten where user_id = u), '[]'::jsonb));
end $$;

-- Een opdracht klaarzetten. Toegestane soorten: toevoegen, klaar, archiveren.
create or replace function public.claude_opdracht(sleutel text, opdracht jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.claude_gebruiker(sleutel); n bigint;
begin
  if jsonb_typeof(opdracht) <> 'object' or not (opdracht->>'soort' = any (array['toevoegen', 'klaar', 'archiveren'])) then
    raise exception 'Onbekende opdracht: gebruik soort toevoegen, klaar of archiveren';
  end if;
  if length(opdracht::text) > 20000 then raise exception 'Opdracht is te groot'; end if;
  if (select count(*) from public.planbord_opdrachten where user_id = u) >= 200 then raise exception 'Te veel wachtende opdrachten'; end if;
  insert into public.planbord_opdrachten (user_id, opdracht) values (u, opdracht) returning id into n;
  return n;
end $$;

-- Een opdracht die nog niet is uitgevoerd weer weghalen
create or replace function public.claude_opdracht_intrekken(sleutel text, opdracht_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.claude_gebruiker(sleutel);
begin
  delete from public.planbord_opdrachten where id = opdracht_id and user_id = u;
  return found;
end $$;

revoke all on function public.claude_sleutel_maken(), public.claude_sleutel_intrekken(), public.claude_toegang_aan(),
  public.claude_gebruiker(text), public.claude_borden(text), public.claude_opdracht(text, jsonb), public.claude_opdracht_intrekken(text, bigint)
  from public, anon, authenticated;
grant execute on function public.claude_sleutel_maken(), public.claude_sleutel_intrekken(), public.claude_toegang_aan() to authenticated;
grant execute on function public.claude_borden(text), public.claude_opdracht(text, jsonb), public.claude_opdracht_intrekken(text, bigint) to anon, authenticated;
