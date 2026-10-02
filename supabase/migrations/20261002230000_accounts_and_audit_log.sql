-- Account safeguards and a readable audit trail.
--
-- Accounts (AUTH-01, S-10, S-11)
--   * The first administrator could not be created the documented way: the
--     role guard refused every role change that did not come from someone
--     who already managed roles. A direct database session (the SQL editor
--     or a migration, never the app's API) is now allowed through, and
--     bootstrap_first_admin(email) is the supported one-step setup.
--   * The system can no longer be left without an active administrator.
--   * profiles.email now follows the sign-in email when it changes, and
--     existing rows are brought into line.
--
-- Audit (S-15, TRACE-01)
--   * Changes to prices, menu, options, discounts, payment methods,
--     suppliers, stock items, staff accounts and settings are recorded with
--     the values before and after.
--   * get_audit_log(from, to, search) lets management read the trail, which
--     until now nothing could.

-- Accounts ------------------------------------------------------------------

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Requests from the app always arrive through the API login role. A
  -- session that is not one of those and carries no user is the database
  -- owner working directly, which is how the first administrator is set up.
  if auth.uid() is null and session_user <> 'authenticator' then
    return new;
  end if;

  if new.role_id is distinct from old.role_id then
    if not public.has_permission('roles.manage') then
      raise exception 'Only an administrator may change user roles';
    end if;
  end if;

  return new;
end;
$$;

create function public.guard_last_active_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_role uuid;
begin
  select id into v_admin_role from public.roles where code = 'ADMIN';

  if old.role_id is distinct from v_admin_role or old.status <> 'ACTIVE' then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE'
     and new.role_id is not distinct from v_admin_role
     and new.status = 'ACTIVE' then
    return new;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id <> old.id
      and p.role_id = v_admin_role
      and p.status = 'ACTIVE'
  ) then
    raise exception
      'This is the only active administrator. Make another account an administrator first.';
  end if;

  return coalesce(new, old);
end;
$$;

revoke all on function public.guard_last_active_admin() from public, anon, authenticated;

create trigger trg_guard_last_active_admin
before update or delete on public.profiles
for each row execute function public.guard_last_active_admin();

create function public.bootstrap_first_admin(p_email text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_email text;
  v_profile public.profiles%rowtype;
begin
  if exists (
    select 1
    from public.profiles p
    join public.roles r on r.id = p.role_id
    where r.code = 'ADMIN'
      and p.status = 'ACTIVE'
  ) then
    raise exception
      'An active administrator already exists. Use User Management in the app.';
  end if;

  select u.id, u.email
  into v_user_id, v_email
  from auth.users u
  where lower(u.email) = lower(btrim(coalesce(p_email, '')));

  if v_user_id is null then
    raise exception
      'No sign-in account exists for that email. Create it under Authentication first.';
  end if;

  insert into public.profiles (id, email, display_name, status, role_id)
  values (
    v_user_id,
    v_email,
    v_email,
    'ACTIVE',
    (select id from public.roles where code = 'ADMIN')
  )
  on conflict (id) do update
  set role_id = excluded.role_id,
      status = 'ACTIVE',
      email = excluded.email,
      archived_at = null
  returning * into v_profile;

  insert into public.audit_logs (
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    null, 'FIRST_ADMIN_BOOTSTRAPPED', 'profiles', v_profile.id::text,
    jsonb_build_object('email', v_email)
  );

  return v_profile;
end;
$$;

-- Run from the SQL editor only. The app cannot call it.
revoke all on function public.bootstrap_first_admin(text)
  from public, anon, authenticated;

create function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set email = new.email
  where id = new.id
    and email is distinct from new.email;

  return new;
end;
$$;

revoke all on function public.sync_profile_email() from public, anon, authenticated;

create trigger on_auth_user_email_changed
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute function public.sync_profile_email();

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and p.email is distinct from u.email;

-- Audit ---------------------------------------------------------------------

create index if not exists idx_audit_logs_created_at
  on public.audit_logs (created_at desc);

create function public.audit_master_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_before jsonb;
  v_after jsonb;
  v_label text;
begin
  v_new := to_jsonb(new) - 'updated_at' - 'created_at';
  v_label := coalesce(
    v_new ->> 'display_name', v_new ->> 'name', v_new ->> 'trade_name',
    v_new ->> 'code', v_new ->> 'key'
  );

  if tg_op = 'INSERT' then
    insert into public.audit_logs (
      actor_user_id, action_code, entity_type, entity_id, new_data
    )
    values (
      auth.uid(),
      upper(tg_table_name) || '_CREATED',
      tg_table_name,
      coalesce(v_new ->> 'id', v_new ->> 'key'),
      v_new || jsonb_build_object('_label', v_label)
    );
    return new;
  end if;

  v_old := to_jsonb(old) - 'updated_at' - 'created_at';

  -- Only the fields that changed are kept, each with its value before and
  -- after.
  select
    jsonb_object_agg(k.key, v_old -> k.key),
    jsonb_object_agg(k.key, v_new -> k.key)
  into v_before, v_after
  from jsonb_object_keys(v_new) as k(key)
  where (v_new -> k.key) is distinct from (v_old -> k.key);

  if v_after is null then
    return new;
  end if;

  insert into public.audit_logs (
    actor_user_id, action_code, entity_type, entity_id, old_data, new_data
  )
  values (
    auth.uid(),
    upper(tg_table_name) || '_UPDATED',
    tg_table_name,
    coalesce(v_new ->> 'id', v_new ->> 'key'),
    v_before,
    v_after || jsonb_build_object('_label', v_label)
  );

  return new;
end;
$$;

revoke all on function public.audit_master_data_change()
  from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'menu_items', 'menu_variants', 'modifier_groups', 'modifiers',
    'discount_types', 'payment_methods', 'suppliers', 'inventory_items',
    'profiles', 'system_settings', 'business_profile'
  ]
  loop
    execute format(
      'create trigger trg_audit_%1$s
         after insert or update on public.%1$I
         for each row execute function public.audit_master_data_change()',
      v_table
    );
  end loop;
end;
$$;

create function public.get_audit_log(
  p_from date,
  p_to date,
  p_search text default null,
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text := public.business_timezone();
  v_start timestamptz;
  v_end timestamptz;
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 300), 1), 1000);
begin
  if not public.has_permission('audit.view') then
    raise exception 'Permission denied';
  end if;

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'A valid date range is required';
  end if;

  v_start := p_from::timestamp at time zone v_tz;
  v_end := (p_to + 1)::timestamp at time zone v_tz;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        a.id,
        a.created_at,
        coalesce(
          nullif(btrim(p.display_name), ''),
          nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
          case when a.actor_user_id is null then 'System' else 'Unknown' end
        ) as actor_name,
        a.action_code,
        a.entity_type,
        a.entity_id,
        coalesce(
          a.new_data ->> '_label',
          a.new_data ->> 'order_number',
          a.new_data ->> 'name'
        ) as label,
        a.old_data,
        a.new_data - '_label' as new_data
      from public.audit_logs a
      left join public.profiles p on p.id = a.actor_user_id
      where a.created_at >= v_start
        and a.created_at < v_end
        and (
          v_search is null
          or a.action_code ilike '%' || v_search || '%'
          or a.entity_type ilike '%' || v_search || '%'
          or coalesce(p.display_name, '') ilike '%' || v_search || '%'
          or coalesce(a.new_data::text, '') ilike '%' || v_search || '%'
          or coalesce(a.old_data::text, '') ilike '%' || v_search || '%'
        )
      order by a.created_at desc
      limit v_limit
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_audit_log(date, date, text, integer)
  from public, anon;
grant execute on function public.get_audit_log(date, date, text, integer)
  to authenticated;
