-- Business details and cash rules that management can edit.
--
-- business_profile holds the name, address and TIN printed on receipts and
-- system_settings holds the shift cash rules. Both were seeded once and no
-- function or screen could change them. These two functions are the only
-- way in; every change is recorded by the audit triggers added in
-- 20261002230000.

create function public.update_business_profile(
  p_trade_name text,
  p_registered_name text default null,
  p_tin text default null,
  p_address_line text default null,
  p_city text default null,
  p_province text default null,
  p_postal_code text default null,
  p_phone text default null,
  p_email text default null
)
returns public.business_profile
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.business_profile%rowtype;
  v_trade_name text := nullif(btrim(coalesce(p_trade_name, '')), '');
  v_email text := nullif(btrim(coalesce(p_email, '')), '');
begin
  if not public.has_permission('settings.manage') then
    raise exception 'Permission denied';
  end if;

  if v_trade_name is null then
    raise exception 'The business name is required';
  end if;

  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'The email address is not valid';
  end if;

  update public.business_profile
  set trade_name = v_trade_name,
      registered_name = nullif(btrim(coalesce(p_registered_name, '')), ''),
      tin = nullif(btrim(coalesce(p_tin, '')), ''),
      address_line = nullif(btrim(coalesce(p_address_line, '')), ''),
      city = nullif(btrim(coalesce(p_city, '')), ''),
      province = nullif(btrim(coalesce(p_province, '')), ''),
      postal_code = nullif(btrim(coalesce(p_postal_code, '')), ''),
      phone = nullif(btrim(coalesce(p_phone, '')), ''),
      email = v_email,
      updated_at = now()
  where id = (select min(id) from public.business_profile)
  returning * into v_profile;

  if not found then
    raise exception 'The business profile has not been set up';
  end if;

  return v_profile;
end;
$$;

revoke all on function public.update_business_profile(
  text, text, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.update_business_profile(
  text, text, text, text, text, text, text, text, text
) to authenticated;

-- Only the rules a manager can safely switch are editable here. The other
-- settings change how sales are recorded and stay a database decision.
create function public.update_shift_cash_rules(
  p_require_opening_cash boolean,
  p_require_closing_cash boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('settings.manage') then
    raise exception 'Permission denied';
  end if;

  if p_require_opening_cash is null or p_require_closing_cash is null then
    raise exception 'Both cash rules need a value';
  end if;

  update public.system_settings
  set value = to_jsonb(p_require_opening_cash),
      updated_at = now(),
      updated_by = auth.uid()
  where key = 'require_opening_cash'
    and value is distinct from to_jsonb(p_require_opening_cash);

  update public.system_settings
  set value = to_jsonb(p_require_closing_cash),
      updated_at = now(),
      updated_by = auth.uid()
  where key = 'require_closing_cash'
    and value is distinct from to_jsonb(p_require_closing_cash);
end;
$$;

revoke all on function public.update_shift_cash_rules(boolean, boolean)
  from public, anon;
grant execute on function public.update_shift_cash_rules(boolean, boolean)
  to authenticated;

-- The app never edits these tables directly.
drop policy if exists "manager manage system settings insert"
  on public.system_settings;
drop policy if exists "manager manage system settings update"
  on public.system_settings;
revoke insert, update, delete, truncate on public.system_settings
  from authenticated, anon;
revoke insert, update, delete, truncate on public.business_profile
  from authenticated, anon;
