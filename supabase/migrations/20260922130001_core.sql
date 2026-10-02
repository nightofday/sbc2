-- Street Bowl Café
-- 0001_core.sql
-- Core identity, security reference data, shifts, devices and shared payment/tax lookups.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.business_profile (
  id smallint primary key default 1 check (id = 1),
  registered_name text,
  trade_name text not null default 'Street Bowl Café',
  tin text,
  branch_code text,
  tax_registration_status text not null default 'UNKNOWN'
    check (tax_registration_status in ('UNKNOWN','VAT','NON_VAT')),
  address_line text,
  city text default 'Davao City',
  province text default 'Davao del Sur',
  postal_code text,
  phone text,
  email text,
  currency_code char(3) not null default 'PHP',
  timezone text not null default 'Asia/Manila',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_business_profile_updated_at
before update on public.business_profile
for each row execute function public.set_updated_at();

create table if not exists public.system_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  terminal_code text not null unique,
  name text not null,
  platform text,
  device_identifier text,
  printer_name text,
  receipt_paper_width_mm smallint check (receipt_paper_width_mm in (58,80) or receipt_paper_width_mm is null),
  is_active boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_devices_updated_at
before update on public.devices
for each row execute function public.set_updated_at();

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  employee_code text unique,
  first_name text,
  last_name text,
  display_name text,
  role_id uuid references public.roles(id),
  status text not null default 'PENDING'
    check (status in ('PENDING','ACTIVE','INACTIVE','SUSPENDED')),
  phone text,
  hired_at date,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_role_id on public.profiles(role_id);
create index if not exists idx_profiles_status on public.profiles(status);

create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- New Supabase Auth users receive a locked-down profile.
-- A manager/admin must later assign role and ACTIVE status through a trusted flow.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email),
    'PENDING'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create table if not exists public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  rate_percent numeric(7,4) not null default 0 check (rate_percent >= 0),
  tax_behavior text not null default 'INCLUSIVE'
    check (tax_behavior in ('INCLUSIVE','EXCLUSIVE','EXEMPT','ZERO_RATED')),
  is_active boolean not null default true,
  effective_from date,
  effective_to date,
  created_at timestamptz not null default now()
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_cash boolean not null default false,
  is_online boolean not null default false,
  requires_reference boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(),
  shift_number bigint generated by default as identity unique,
  employee_id uuid not null references public.profiles(id),
  device_id uuid references public.devices(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  opening_cash numeric(14,2) check (opening_cash is null or opening_cash >= 0),
  closing_cash_counted numeric(14,2) check (closing_cash_counted is null or closing_cash_counted >= 0),
  expected_closing_cash numeric(14,2),
  cash_variance numeric(14,2),
  status text not null default 'OPEN'
    check (status in ('OPEN','CLOSED','FORCED_CLOSED')),
  closing_notes text,
  closed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'OPEN' and ended_at is null) or status <> 'OPEN')
);

create unique index if not exists uq_one_open_shift_per_employee
  on public.shifts(employee_id)
  where status = 'OPEN';

create index if not exists idx_shifts_started_at on public.shifts(started_at desc);
create index if not exists idx_shifts_employee on public.shifts(employee_id, started_at desc);

create trigger trg_shifts_updated_at
before update on public.shifts
for each row execute function public.set_updated_at();

create table if not exists public.shift_cash_movements (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.shifts(id),
  movement_type text not null
    check (movement_type in ('PAY_IN','PAY_OUT','CASH_DROP','CORRECTION')),
  amount numeric(14,2) not null check (amount > 0),
  reason text not null,
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_shift_cash_movements_shift
  on public.shift_cash_movements(shift_id, created_at);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id) on delete set null,
  action_code text not null,
  entity_type text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_entity
  on public.audit_logs(entity_type, entity_id, created_at desc);
create index if not exists idx_audit_logs_actor
  on public.audit_logs(actor_user_id, created_at desc);
