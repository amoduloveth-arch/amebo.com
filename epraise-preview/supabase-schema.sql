-- ============================================================
--  E.PRAISE COUTURE'S — Supabase schema
--  Run this once in Supabase → SQL Editor → New query → Run
--  Safe to re-run: every statement is idempotent.
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- 1. ADMINS
--    A user is an administrator only if they have a row here.
--    There is no public path that inserts into this table.
-- ------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

drop policy if exists "admin reads own row" on public.admins;
create policy "admin reads own row"
  on public.admins for select
  to authenticated
  using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 2. DESIGNS
-- ------------------------------------------------------------
create table if not exists public.designs (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(trim(title)) between 1 and 120),
  category    text not null check (category in (
                'dresses','bridal','casual','traditional','suits','accessories'
              )),
  description text check (char_length(description) <= 4000),
  price       numeric(12,2) check (price is null or price >= 0),
  currency    text not null default 'NGN',
  sizes       text[] not null default '{}',
  colors      text[] not null default '{}',
  available   boolean not null default true,
  published   boolean not null default true,
  images      text[] not null default '{}',
  position    integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists designs_published_idx on public.designs (published, created_at desc);

alter table public.designs enable row level security;

-- Public: may read ONLY published designs.
drop policy if exists "public reads published designs" on public.designs;
create policy "public reads published designs"
  on public.designs for select
  to anon, authenticated
  using (published = true);

-- Admin: full read of everything, including drafts.
drop policy if exists "admin reads all designs" on public.designs;
create policy "admin reads all designs"
  on public.designs for select
  to authenticated
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- Admin: create / update / delete.
drop policy if exists "admin inserts designs" on public.designs;
create policy "admin inserts designs"
  on public.designs for insert
  to authenticated
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

drop policy if exists "admin updates designs" on public.designs;
create policy "admin updates designs"
  on public.designs for update
  to authenticated
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

drop policy if exists "admin deletes designs" on public.designs;
create policy "admin deletes designs"
  on public.designs for delete
  to authenticated
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- keep updated_at honest
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists designs_touch_updated_at on public.designs;
create trigger designs_touch_updated_at
  before update on public.designs
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- 3. IMAGE STORAGE
--    Public bucket for reading, admin-only for writing.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('designs', 'designs', true)
on conflict (id) do update set public = true;

drop policy if exists "public reads design images" on storage.objects;
create policy "public reads design images"
  on storage.objects for select
  using (bucket_id = 'designs');

drop policy if exists "admin uploads design images" on storage.objects;
create policy "admin uploads design images"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'designs'
    and exists (select 1 from public.admins a where a.user_id = auth.uid())
  );

drop policy if exists "admin updates design images" on storage.objects;
create policy "admin updates design images"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'designs'
    and exists (select 1 from public.admins a where a.user_id = auth.uid())
  );

drop policy if exists "admin deletes design images" on storage.objects;
create policy "admin deletes design images"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'designs'
    and exists (select 1 from public.admins a where a.user_id = auth.uid())
  );

-- ============================================================
-- 4. MAKE YOURSELF THE ADMIN  (run after creating your user)
--
--   insert into public.admins (user_id, email)
--   select id, email from auth.users where email = 'you@example.com'
--   on conflict (user_id) do nothing;
--
-- ============================================================
