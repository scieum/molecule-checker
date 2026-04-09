-- Molecule Checker — initial schema
--
-- Tables:
--   profiles         — one row per auth user (nickname, school info)
--   gallery_entries  — user's saved molecule analyses
--   hall_of_fame     — public leaderboard of large molecules
--
-- Storage:
--   molecule-images  — public bucket for uploaded photos
--
-- Auth model: anonymous sign-ins are enabled, so every visitor gets a
-- durable auth.users row without friction. RLS policies scope reads and
-- writes of private data to the owning user_id.

-- =========================================================================
-- Extensions
-- =========================================================================
create extension if not exists "pgcrypto";

-- =========================================================================
-- profiles
-- =========================================================================
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  nickname     text not null check (char_length(nickname) between 1 and 40),
  school_code  text,
  school_name  text,
  school_kind  text,
  region_code  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists profiles_nickname_idx on public.profiles (nickname);

alter table public.profiles enable row level security;

drop policy if exists "profiles are readable by owner" on public.profiles;
create policy "profiles are readable by owner"
  on public.profiles for select
  using (auth.uid() = user_id);

drop policy if exists "profiles insertable by owner" on public.profiles;
create policy "profiles insertable by owner"
  on public.profiles for insert
  with check (auth.uid() = user_id);

drop policy if exists "profiles updatable by owner" on public.profiles;
create policy "profiles updatable by owner"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "profiles deletable by owner" on public.profiles;
create policy "profiles deletable by owner"
  on public.profiles for delete
  using (auth.uid() = user_id);

-- =========================================================================
-- gallery_entries
-- =========================================================================
create table if not exists public.gallery_entries (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  molecule_name_kr text,
  molecule_name_en text,
  formula          text,
  is_valid         boolean,
  atoms            integer,
  image_path       text,
  confidence       text,
  explanation      text,
  created_at       timestamptz not null default now()
);

create index if not exists gallery_entries_user_idx
  on public.gallery_entries (user_id, created_at desc);

alter table public.gallery_entries enable row level security;

drop policy if exists "gallery readable by owner" on public.gallery_entries;
create policy "gallery readable by owner"
  on public.gallery_entries for select
  using (auth.uid() = user_id);

drop policy if exists "gallery insertable by owner" on public.gallery_entries;
create policy "gallery insertable by owner"
  on public.gallery_entries for insert
  with check (auth.uid() = user_id);

drop policy if exists "gallery deletable by owner" on public.gallery_entries;
create policy "gallery deletable by owner"
  on public.gallery_entries for delete
  using (auth.uid() = user_id);

-- =========================================================================
-- hall_of_fame
-- =========================================================================
create table if not exists public.hall_of_fame (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete set null,
  nickname    text not null,
  school      text,
  molecule    text not null,
  formula     text,
  atoms       integer not null check (atoms > 0),
  image_path  text,
  created_at  timestamptz not null default now()
);

create index if not exists hall_of_fame_atoms_idx
  on public.hall_of_fame (atoms desc, created_at desc);

alter table public.hall_of_fame enable row level security;

drop policy if exists "hall readable by anyone" on public.hall_of_fame;
create policy "hall readable by anyone"
  on public.hall_of_fame for select
  using (true);

drop policy if exists "hall insertable by authenticated" on public.hall_of_fame;
create policy "hall insertable by authenticated"
  on public.hall_of_fame for insert
  with check (auth.uid() is not null and auth.uid() = user_id);

drop policy if exists "hall deletable by owner" on public.hall_of_fame;
create policy "hall deletable by owner"
  on public.hall_of_fame for delete
  using (auth.uid() = user_id);

-- =========================================================================
-- Storage bucket: molecule-images
-- =========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'molecule-images',
  'molecule-images',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Each user uploads under their own uid prefix: `{auth.uid}/...`
drop policy if exists "molecule-images public read" on storage.objects;
create policy "molecule-images public read"
  on storage.objects for select
  using (bucket_id = 'molecule-images');

drop policy if exists "molecule-images owner insert" on storage.objects;
create policy "molecule-images owner insert"
  on storage.objects for insert
  with check (
    bucket_id = 'molecule-images'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "molecule-images owner delete" on storage.objects;
create policy "molecule-images owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'molecule-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- =========================================================================
-- updated_at trigger for profiles
-- =========================================================================
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.tg_set_updated_at();
