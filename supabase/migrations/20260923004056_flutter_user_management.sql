-- User management read model and profile management helpers.

alter table public.profiles
  add column if not exists email text;

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and p.email is distinct from u.email;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    email,
    display_name,
    status
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email),
    'PENDING'
  )
  on conflict (id) do update set
    email = excluded.email;

  return new;
end;
$$;

create or replace view public.v_user_management
with (security_invoker = true)
as
select
  p.id,
  p.email,
  p.employee_code,
  p.display_name,
  p.first_name,
  p.last_name,
  p.phone,
  p.status,
  p.role_id,
  r.code as role_code,
  r.name as role_name,
  p.created_at,
  p.updated_at
from public.profiles p
left join public.roles r on r.id = p.role_id;

grant select on public.v_user_management to authenticated;
revoke all on public.v_user_management from anon;

create or replace function public.update_employee_profile(
  p_user_id uuid,
  p_display_name text,
  p_status text,
  p_role_id uuid default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_current_role uuid;
  v_status text;
begin
  if not public.has_permission('users.manage') then
    raise exception 'Permission denied';
  end if;

  select role_id
  into v_current_role
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'User profile not found';
  end if;

  v_status := upper(btrim(coalesce(p_status,'')));

  if v_status not in ('PENDING','ACTIVE','INACTIVE','SUSPENDED') then
    raise exception 'Invalid user status';
  end if;

  if p_user_id = auth.uid() and v_status <> 'ACTIVE' then
    raise exception 'You cannot deactivate or suspend your own account';
  end if;

  if p_role_id is distinct from v_current_role
     and not public.has_permission('roles.manage') then
    raise exception 'Only an administrator may change user roles';
  end if;

  if p_role_id is not null and not exists (
    select 1 from public.roles where id = p_role_id
  ) then
    raise exception 'Invalid role';
  end if;

  update public.profiles
  set
    display_name = nullif(btrim(coalesce(p_display_name,'')), ''),
    status = v_status,
    role_id = p_role_id,
    archived_at = case
      when v_status = 'INACTIVE' then coalesce(archived_at, now())
      else null
    end
  where id = p_user_id
  returning * into v_profile;

  return v_profile;
end;
$$;

revoke all on function public.update_employee_profile(uuid,text,text,uuid)
from public, anon;
grant execute on function public.update_employee_profile(uuid,text,text,uuid)
to authenticated;
