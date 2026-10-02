-- 0003_menu_orders.sql
-- Menu, variants, modifiers, recipes, orders, discounts, payments and refunds.

create table if not exists public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_menu_categories_updated_at
before update on public.menu_categories
for each row execute function public.set_updated_at();

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  category_id uuid references public.menu_categories(id),
  image_url text,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_menu_items_category on public.menu_items(category_id);
create index if not exists idx_menu_items_active on public.menu_items(is_active);

create trigger trg_menu_items_updated_at
before update on public.menu_items
for each row execute function public.set_updated_at();

create table if not exists public.menu_variants (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.menu_items(id),
  sku text unique,
  name text not null default 'Standard',
  price numeric(14,2) not null check (price >= 0),
  tax_rate_id uuid references public.tax_rates(id),
  is_default boolean not null default false,
  is_active boolean not null default true,
  track_finished_inventory boolean not null default false,
  finished_inventory_item_id uuid references public.inventory_items(id),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (track_finished_inventory = false)
    or finished_inventory_item_id is not null
  )
);

create unique index if not exists uq_default_variant_per_menu_item
  on public.menu_variants(menu_item_id)
  where is_default = true;

create index if not exists idx_menu_variants_item on public.menu_variants(menu_item_id);

create trigger trg_menu_variants_updated_at
before update on public.menu_variants
for each row execute function public.set_updated_at();

create table if not exists public.modifier_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  min_selections integer not null default 0 check (min_selections >= 0),
  max_selections integer check (max_selections is null or max_selections > 0),
  is_required boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  check (max_selections is null or max_selections >= min_selections)
);

create table if not exists public.modifiers (
  id uuid primary key default gen_random_uuid(),
  modifier_group_id uuid not null references public.modifier_groups(id),
  name text not null,
  price_delta numeric(14,2) not null default 0,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (modifier_group_id, name)
);

create table if not exists public.menu_item_modifier_groups (
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  modifier_group_id uuid not null references public.modifier_groups(id) on delete cascade,
  sort_order integer not null default 0,
  primary key (menu_item_id, modifier_group_id)
);

create table if not exists public.variant_recipe_components (
  id uuid primary key default gen_random_uuid(),
  menu_variant_id uuid not null references public.menu_variants(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id),
  quantity_base_uom numeric(14,4) not null check (quantity_base_uom > 0),
  wastage_percent numeric(7,4) not null default 0 check (wastage_percent >= 0),
  unique (menu_variant_id, inventory_item_id)
);

create table if not exists public.modifier_recipe_components (
  id uuid primary key default gen_random_uuid(),
  modifier_id uuid not null references public.modifiers(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id),
  quantity_base_uom numeric(14,4) not null check (quantity_base_uom > 0),
  wastage_percent numeric(7,4) not null default 0 check (wastage_percent >= 0),
  unique (modifier_id, inventory_item_id)
);

create table if not exists public.discount_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  calculation_method text not null default 'MANUAL_AMOUNT'
    check (calculation_method in ('MANUAL_AMOUNT','PERCENTAGE','FIXED_AMOUNT')),
  default_value numeric(14,4),
  requires_id boolean not null default false,
  requires_authorization boolean not null default false,
  is_tax_exempt_related boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated by default as identity unique,
  client_request_id uuid unique,
  order_type text not null
    check (order_type in ('DINE_IN','TAKE_OUT','DELIVERY')),
  source_code text not null default 'POS'
    check (source_code in ('POS','MANUAL_DELIVERY','PHONE','OTHER')),
  status text not null default 'OPEN'
    check (status in (
      'OPEN',
      'PENDING_PAYMENT',
      'COMPLETED',
      'VOIDED',
      'PARTIALLY_REFUNDED',
      'REFUNDED',
      'CANCELLED'
    )),
  payment_status text not null default 'UNPAID'
    check (payment_status in (
      'UNPAID',
      'PARTIALLY_PAID',
      'PAID',
      'PARTIALLY_REFUNDED',
      'REFUNDED'
    )),
  created_by_user_id uuid references public.profiles(id) on delete set null,
  employee_name_snapshot text,
  shift_id uuid references public.shifts(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  customer_name text,
  table_number text,
  delivery_provider text,
  delivery_reference text,
  delivery_contact_name text,
  delivery_phone text,
  delivery_address text,
  notes text,
  subtotal numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (order_type <> 'DINE_IN')
    or table_number is not null
  )
);

create index if not exists idx_orders_created_at on public.orders(created_at desc);
create index if not exists idx_orders_shift on public.orders(shift_id, created_at desc);
create index if not exists idx_orders_creator on public.orders(created_by_user_id, created_at desc);
create index if not exists idx_orders_status on public.orders(status, created_at desc);

create trigger trg_orders_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  menu_variant_id uuid references public.menu_variants(id) on delete set null,
  item_name_snapshot text not null,
  variant_name_snapshot text,
  quantity numeric(14,4) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  modifier_total_per_unit numeric(14,2) not null default 0,
  line_subtotal numeric(14,2) not null check (line_subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  special_instructions text,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_items_order on public.order_items(order_id);

create table if not exists public.order_item_modifiers (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  modifier_id uuid references public.modifiers(id) on delete set null,
  modifier_name_snapshot text not null,
  quantity numeric(14,4) not null default 1 check (quantity > 0),
  price_delta numeric(14,2) not null default 0,
  line_amount numeric(14,2) not null default 0
);

create index if not exists idx_order_item_modifiers_item on public.order_item_modifiers(order_item_id);

create table if not exists public.order_discounts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  discount_type_id uuid not null references public.discount_types(id),
  discount_name_snapshot text not null,
  discount_amount numeric(14,2) not null check (discount_amount >= 0),
  reference_name text,
  reference_number text,
  authorized_by uuid references public.profiles(id) on delete set null,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_discounts_order on public.order_discounts(order_id);

create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(),
  refund_number bigint generated by default as identity unique,
  order_id uuid not null references public.orders(id),
  refund_type text not null check (refund_type in ('FULL','PARTIAL')),
  status text not null default 'COMPLETED'
    check (status in ('PENDING','COMPLETED','VOIDED')),
  reason text not null,
  total_amount numeric(14,2) not null check (total_amount > 0),
  requested_by uuid references public.profiles(id) on delete set null,
  authorized_by uuid references public.profiles(id) on delete set null,
  shift_id uuid references public.shifts(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_refunds_order on public.refunds(order_id, created_at desc);

create table if not exists public.refund_items (
  id uuid primary key default gen_random_uuid(),
  refund_id uuid not null references public.refunds(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id),
  quantity numeric(14,4) not null check (quantity > 0),
  refund_amount numeric(14,2) not null check (refund_amount >= 0),
  restock_approved boolean not null default false,
  notes text
);

create index if not exists idx_refund_items_refund on public.refund_items(refund_id);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  refund_id uuid references public.refunds(id),
  payment_method_id uuid not null references public.payment_methods(id),
  transaction_type text not null default 'PAYMENT'
    check (transaction_type in ('PAYMENT','REFUND')),
  status text not null default 'COMPLETED'
    check (status in ('PENDING','COMPLETED','FAILED','VOIDED')),
  amount numeric(14,2) not null check (amount > 0),
  amount_tendered numeric(14,2),
  change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
  external_provider text,
  external_reference text,
  idempotency_key uuid unique,
  processed_by uuid references public.profiles(id) on delete set null,
  shift_id uuid references public.shifts(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  processed_at timestamptz not null default now(),
  notes text,
  check (
    (transaction_type = 'REFUND' and refund_id is not null)
    or transaction_type = 'PAYMENT'
  )
);

create index if not exists idx_payments_order on public.payments(order_id, processed_at);
create index if not exists idx_payments_shift on public.payments(shift_id, processed_at);

create table if not exists public.order_actions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  action_type text not null
    check (action_type in ('VOID','REFUND','CANCEL','REOPEN','MANAGER_OVERRIDE')),
  reason text,
  performed_by uuid references public.profiles(id) on delete set null,
  authorized_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_actions_order on public.order_actions(order_id, created_at desc);

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_status_history_order
  on public.order_status_history(order_id, created_at);
