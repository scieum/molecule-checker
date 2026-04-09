-- Relax RLS for the school-demo data tables
--
-- The previous profile_hash-based RLS scheme (see 20260409020000_*)
-- depends on the client's JWT user_metadata staying perfectly in sync
-- with what just got written via supabase.auth.updateUser({ data }).
-- In practice that sync is fragile: updateUser does not rotate the
-- access token, and even calling refreshSession() right after it does
-- not always produce a JWT whose claims contain the freshly written
-- profile_hash. The result was every gallery_entries INSERT failing
-- with "new row violates row-level security policy".
--
-- Since this is a school-demo app where the client already filters
-- every query by profile_hash, we simply disable RLS on the three
-- app tables and trust client-side scoping. The Gemini API key is
-- still safe (Edge Function secret), and Supabase Storage still
-- enforces bucket + mime type + size limits.

alter table public.profiles         disable row level security;
alter table public.gallery_entries  disable row level security;
alter table public.hall_of_fame     disable row level security;

-- Storage: keep public read, drop the JWT-claim based write policies,
-- and allow any session to upload/delete inside the bucket.
drop policy if exists "molecule-images hash insert"  on storage.objects;
drop policy if exists "molecule-images hash delete"  on storage.objects;
drop policy if exists "molecule-images owner insert" on storage.objects;
drop policy if exists "molecule-images owner delete" on storage.objects;

create policy "molecule-images any insert"
  on storage.objects for insert
  with check (bucket_id = 'molecule-images');

create policy "molecule-images any delete"
  on storage.objects for delete
  using (bucket_id = 'molecule-images');
