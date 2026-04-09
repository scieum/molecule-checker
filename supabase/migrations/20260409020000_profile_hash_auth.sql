-- Migrate to profile_hash based auth
--
-- Replaces the auth.uid() based RLS scheme with one driven by a custom
-- `profile_hash` claim in the user's JWT user_metadata. The hash is
-- computed client-side from sha256("<nickname-lower>:<code-upper>") and
-- stashed via supabase.auth.updateUser({ data: { profile_hash, ... } }),
-- which works on anonymous users and never triggers GoTrue's email
-- deliverability check.
--
-- Two anonymous users on different devices that share the same hash
-- (because they typed the same nickname + code) end up with the same
-- profile_hash claim and therefore see the same rows.
--
-- This migration is additive on the data side (adds a column, drops
-- and recreates policies) so existing rows aren't deleted, but rows
-- created before this migration are unreachable until they're back-
-- filled with the right profile_hash. For a school demo we just let
-- pre-existing rows go stale and start fresh.

-- =========================================================================
-- profiles
-- =========================================================================
alter table public.profiles
  add column if not exists profile_hash text;

-- A given (nickname, code) pair maps to exactly one profile row.
-- Use a real UNIQUE constraint (not a partial index) so PostgREST's
-- upsert `onConflict: 'profile_hash'` path can actually use it. NULLs
-- are still allowed to repeat under Postgres's default behavior.
-- Drop any earlier partial-index version first so the constraint name
-- is free to be reused.
drop index if exists public.profiles_profile_hash_unique;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_profile_hash_unique'
  ) then
    alter table public.profiles
      add constraint profiles_profile_hash_unique unique (profile_hash);
  end if;
end $$;

drop policy if exists "profiles are readable by owner" on public.profiles;
drop policy if exists "profiles insertable by owner" on public.profiles;
drop policy if exists "profiles updatable by owner" on public.profiles;
drop policy if exists "profiles deletable by owner" on public.profiles;
drop policy if exists "profiles readable by hash" on public.profiles;
drop policy if exists "profiles insertable by hash" on public.profiles;
drop policy if exists "profiles updatable by hash" on public.profiles;
drop policy if exists "profiles deletable by hash" on public.profiles;

create policy "profiles readable by hash"
  on public.profiles for select
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "profiles insertable by hash"
  on public.profiles for insert
  with check (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "profiles updatable by hash"
  on public.profiles for update
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'))
  with check (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "profiles deletable by hash"
  on public.profiles for delete
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

-- =========================================================================
-- gallery_entries
-- =========================================================================
alter table public.gallery_entries
  add column if not exists profile_hash text;

create index if not exists gallery_entries_profile_hash_idx
  on public.gallery_entries (profile_hash, created_at desc);

drop policy if exists "gallery readable by owner" on public.gallery_entries;
drop policy if exists "gallery insertable by owner" on public.gallery_entries;
drop policy if exists "gallery deletable by owner" on public.gallery_entries;
drop policy if exists "gallery readable by hash" on public.gallery_entries;
drop policy if exists "gallery insertable by hash" on public.gallery_entries;
drop policy if exists "gallery deletable by hash" on public.gallery_entries;

create policy "gallery readable by hash"
  on public.gallery_entries for select
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "gallery insertable by hash"
  on public.gallery_entries for insert
  with check (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "gallery deletable by hash"
  on public.gallery_entries for delete
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

-- =========================================================================
-- hall_of_fame
-- =========================================================================
alter table public.hall_of_fame
  add column if not exists profile_hash text;

create index if not exists hall_of_fame_profile_hash_idx
  on public.hall_of_fame (profile_hash);

drop policy if exists "hall readable by anyone" on public.hall_of_fame;
drop policy if exists "hall insertable by authenticated" on public.hall_of_fame;
drop policy if exists "hall deletable by owner" on public.hall_of_fame;
drop policy if exists "hall insertable by hash" on public.hall_of_fame;
drop policy if exists "hall deletable by hash" on public.hall_of_fame;

create policy "hall readable by anyone"
  on public.hall_of_fame for select
  using (true);

create policy "hall insertable by hash"
  on public.hall_of_fame for insert
  with check (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

create policy "hall deletable by hash"
  on public.hall_of_fame for delete
  using (profile_hash = (auth.jwt() -> 'user_metadata' ->> 'profile_hash'));

-- =========================================================================
-- Storage bucket: molecule-images — switch to profile_hash prefix
-- =========================================================================
drop policy if exists "molecule-images public read" on storage.objects;
drop policy if exists "molecule-images owner insert" on storage.objects;
drop policy if exists "molecule-images owner delete" on storage.objects;
drop policy if exists "molecule-images hash insert" on storage.objects;
drop policy if exists "molecule-images hash delete" on storage.objects;

create policy "molecule-images public read"
  on storage.objects for select
  using (bucket_id = 'molecule-images');

create policy "molecule-images hash insert"
  on storage.objects for insert
  with check (
    bucket_id = 'molecule-images'
    and (storage.foldername(name))[1] = (auth.jwt() -> 'user_metadata' ->> 'profile_hash')
  );

create policy "molecule-images hash delete"
  on storage.objects for delete
  using (
    bucket_id = 'molecule-images'
    and (storage.foldername(name))[1] = (auth.jwt() -> 'user_metadata' ->> 'profile_hash')
  );
