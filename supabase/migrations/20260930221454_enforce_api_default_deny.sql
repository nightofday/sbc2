-- Phase 9: make the public Data API fail closed.
--
-- Authentication is handled by Supabase Auth. The unauthenticated `anon` role
-- does not need access to Street Bowl Cafe business data or RPCs. Authenticated
-- access remains controlled by the explicit grants and RLS policies installed
-- by the earlier migrations.

revoke all on schema public from public, anon;
grant usage on schema public to authenticated, service_role;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from public, anon;

-- The private archive schema is never part of the client-facing API.
revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke execute on all functions in schema private
from public, anon, authenticated;

-- Future objects must be deliberately exposed in the migration that creates
-- them. This prevents a new table, sequence, or function from becoming an API
-- surface only because PostgreSQL supplied a permissive default privilege.
alter default privileges in schema public
revoke all on tables from public, anon, authenticated;

alter default privileges in schema public
revoke all on sequences from public, anon, authenticated;

alter default privileges in schema public
revoke execute on functions from public, anon, authenticated;

alter default privileges in schema private
revoke all on tables from public, anon, authenticated;

alter default privileges in schema private
revoke all on sequences from public, anon, authenticated;

alter default privileges in schema private
revoke execute on functions from public, anon, authenticated;
