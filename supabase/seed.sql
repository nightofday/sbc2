-- Street Bowl Café reference data seed.
-- Safe to customize before production.
-- No Auth user is created here.

insert into public.business_profile (
  id,
  trade_name,
  city,
  province,
  currency_code,
  timezone,
  tax_registration_status
)
values (
  1,
  'Street Bowl Café',
  'Davao City',
  'Davao del Sur',
  'PHP',
  'Asia/Manila',
  'UNKNOWN'
)
on conflict (id) do update set
  trade_name = excluded.trade_name,
  city = excluded.city,
  province = excluded.province,
  currency_code = excluded.currency_code,
  timezone = excluded.timezone;

insert into public.system_settings(key,value,description) values
  ('require_opening_cash','false'::jsonb,'Require cashier to enter opening cash when starting a shift'),
  ('require_closing_cash','false'::jsonb,'Require counted cash when ending a shift'),
  ('expiry_warning_days','7'::jsonb,'Default number of days before expiry warning'),
  ('allow_split_payments','false'::jsonb,'UI feature flag; database already supports multiple payments'),
  ('allow_offline_orders','false'::jsonb,'Future feature flag for offline-first POS flow'),
  ('auto_issue_sales_invoice','true'::jsonb,'Issue a sales invoice when checkout succeeds')
on conflict (key) do update set
  value = excluded.value,
  description = excluded.description;

insert into public.roles(code,name,description) values
  ('ADMIN','Administrator','System administration and full business access'),
  ('MANAGER','Manager','Business management, approvals, finance, purchasing and reporting'),
  ('CASHIER','Cashier','POS/order processing and own shift operations')
on conflict (code) do nothing;

insert into public.permissions(code,name,description) values
  ('roles.manage','Manage Roles','Manage roles and permissions'),
  ('users.view','View Users','View employee/user records'),
  ('users.manage','Manage Users','Activate, edit and manage employee profiles'),
  ('devices.manage','Manage Devices','Register and manage POS devices'),
  ('settings.manage','Manage Settings','Manage business/system settings'),
  ('shift.start','Start Shift','Start own cashier shift'),
  ('shift.manage','Manage Shifts','View/manage all shifts'),
  ('shift.cash_movement','Shift Cash Movement','Record pay-in/pay-out/cash-drop movements'),
  ('menu.view','View Menu','View menu setup'),
  ('menu.manage','Manage Menu','Manage menu, variants, modifiers and recipes'),
  ('orders.create','Create Orders','Create POS orders'),
  ('orders.checkout','Checkout Orders','Complete payment and checkout'),
  ('orders.manage_all','Manage All Orders','View/manage all staff orders'),
  ('orders.void','Void Orders','Void unpaid/open orders'),
  ('orders.refund','Refund Orders','Create full/partial refunds'),
  ('discounts.apply','Apply Discounts','Apply order discounts'),
  ('discounts.manage','Manage Discounts','Manage discount definitions'),
  ('inventory.view','View Inventory','View inventory and lots'),
  ('inventory.manage','Manage Inventory','Manage inventory master data'),
  ('inventory.adjust','Adjust Inventory','Perform stock counts/manual adjustments'),
  ('suppliers.view','View Suppliers','View supplier information'),
  ('suppliers.manage','Manage Suppliers','Manage suppliers and supplier-item mappings'),
  ('purchases.view','View Purchases','View purchase orders/receipts/bills'),
  ('purchases.manage','Manage Purchases','Create/approve/manage purchasing'),
  ('purchases.receive','Receive Purchases','Receive/post supplier deliveries'),
  ('expenses.view','View Expenses','View operating expenses'),
  ('expenses.manage','Manage Expenses','Create/edit/void expenses'),
  ('finance.view','View Finance','View financial/payment/invoice information'),
  ('finance.manage','Manage Finance','Manage supplier payments/invoice configuration'),
  ('reports.view','View Reports','View business reports'),
  ('audit.view','View Audit Log','View audit history')
on conflict (code) do nothing;

-- ADMIN gets every permission.
insert into public.role_permissions(role_id,permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code = 'ADMIN'
on conflict do nothing;

-- MANAGER gets all business permissions except role administration.
insert into public.role_permissions(role_id,permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'users.view','users.manage','devices.manage','settings.manage',
  'shift.start','shift.manage','shift.cash_movement',
  'menu.view','menu.manage',
  'orders.create','orders.checkout','orders.manage_all','orders.void','orders.refund',
  'discounts.apply','discounts.manage',
  'inventory.view','inventory.manage','inventory.adjust',
  'suppliers.view','suppliers.manage',
  'purchases.view','purchases.manage','purchases.receive',
  'expenses.view','expenses.manage',
  'finance.view','finance.manage',
  'reports.view','audit.view'
)
where r.code = 'MANAGER'
on conflict do nothing;

-- CASHIER keeps narrow operational access.
insert into public.role_permissions(role_id,permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'shift.start',
  'shift.cash_movement',
  'menu.view',
  'orders.create',
  'orders.checkout',
  'inventory.view'
)
where r.code = 'CASHIER'
on conflict do nothing;

insert into public.payment_methods(code,name,is_cash,is_online,requires_reference,sort_order) values
  ('CASH','Cash',true,false,false,10),
  ('GCASH','GCash',false,true,true,20),
  ('MAYA','Maya',false,true,true,30),
  ('CARD','Debit / Credit Card',false,true,true,40),
  ('BANK_TRANSFER','Bank Transfer',false,true,true,50),
  ('OTHER','Other',false,false,false,99)
on conflict (code) do nothing;

insert into public.tax_rates(code,name,rate_percent,tax_behavior,is_active) values
  ('UNCONFIRMED','Tax Status To Be Confirmed',0,'EXEMPT',true),
  ('VAT_12_INCLUSIVE','VAT 12% Inclusive',12,'INCLUSIVE',true),
  ('VAT_EXEMPT','VAT Exempt',0,'EXEMPT',true),
  ('ZERO_RATED','Zero Rated',0,'ZERO_RATED',true)
on conflict (code) do nothing;

insert into public.units_of_measure(code,name,dimension,factor_to_dimension_base) values
  ('g','Gram','MASS',1),
  ('kg','Kilogram','MASS',1000),
  ('ml','Milliliter','VOLUME',1),
  ('L','Liter','VOLUME',1000),
  ('pc','Piece','COUNT',1),
  ('box','Box','COUNT',1),
  ('pack','Pack','COUNT',1)
on conflict (code) do nothing;

insert into public.inventory_categories(name,description) values
  ('Packaging','Cups, lids, takeout packaging and similar materials'),
  ('Finished Goods','Ready-to-sell stock such as bottled/canned products')
on conflict (name) do nothing;

insert into public.menu_categories(name,sort_order) values
  ('Coffee',10),
  ('Non-Coffee Beverages',20),
  ('Rice Bowls / Meals',30),
  ('Snacks',40),
  ('Baked Goods',50),
  ('Other',99)
on conflict (name) do nothing;

insert into public.discount_types(
  code,name,calculation_method,default_value,requires_id,requires_authorization,is_tax_exempt_related,notes
) values
  ('SENIOR','Senior Citizen','PERCENTAGE',20,true,true,true,'Final eligibility and tax calculation must be validated against current Philippine requirements and the business setup.'),
  ('PWD','PWD','PERCENTAGE',20,true,true,true,'Final eligibility and tax calculation must be validated against current Philippine requirements and the business setup.'),
  ('PROMO_PERCENT','Promotional Percentage','PERCENTAGE',null,false,true,false,null),
  ('PROMO_FIXED','Promotional Fixed Amount','FIXED_AMOUNT',null,false,true,false,null),
  ('MANUAL','Manual Discount','MANUAL_AMOUNT',null,false,true,false,null)
on conflict (code) do nothing;

insert into public.expense_categories(code,name) values
  ('INGREDIENTS','Ingredients / Grocery'),
  ('UTILITIES','Utilities'),
  ('RENT','Rent'),
  ('SUPPLIES','Non-Inventory Supplies'),
  ('MAINTENANCE','Maintenance / Repair'),
  ('EQUIPMENT','Equipment'),
  ('DELIVERY_FEES','Delivery / Transport'),
  ('MARKETING','Marketing'),
  ('OTHER','Other')
on conflict (code) do nothing;

insert into public.invoice_sequences(code,prefix,next_number,number_width,is_active)
values ('SALES_INVOICE','SI-',1,8,true)
on conflict (code) do nothing;


-- Development POS menu data used by the Flutter prototype.
-- Safe to rerun because variants use stable SKUs.
with wanted(name, category_name, sku, price) as (
  values
    ('Chicken Bowl','Rice Bowls / Meals','PRD-001',150.00::numeric),
    ('Beef Bowl','Rice Bowls / Meals','PRD-002',170.00::numeric),
    ('Iced Coffee','Coffee','PRD-003',150.00::numeric),
    ('Hot Coffee','Coffee','PRD-004',120.00::numeric),
    ('Bottled Water','Non-Coffee Beverages','PRD-005',40.00::numeric),
    ('Chocolate Cake','Baked Goods','PRD-006',180.00::numeric),
    ('Cookie','Baked Goods','PRD-007',50.00::numeric),
    ('Coca-Cola','Non-Coffee Beverages','PRD-008',60.00::numeric)
)
insert into public.menu_items(name, category_id, is_active)
select w.name, mc.id, true
from wanted w
join public.menu_categories mc on mc.name = w.category_name
where not exists (
  select 1
  from public.menu_variants mv
  where mv.sku = w.sku
);

with wanted(name, category_name, sku, price) as (
  values
    ('Chicken Bowl','Rice Bowls / Meals','PRD-001',150.00::numeric),
    ('Beef Bowl','Rice Bowls / Meals','PRD-002',170.00::numeric),
    ('Iced Coffee','Coffee','PRD-003',150.00::numeric),
    ('Hot Coffee','Coffee','PRD-004',120.00::numeric),
    ('Bottled Water','Non-Coffee Beverages','PRD-005',40.00::numeric),
    ('Chocolate Cake','Baked Goods','PRD-006',180.00::numeric),
    ('Cookie','Baked Goods','PRD-007',50.00::numeric),
    ('Coca-Cola','Non-Coffee Beverages','PRD-008',60.00::numeric)
)
insert into public.menu_variants(
  menu_item_id,
  sku,
  name,
  price,
  is_default,
  is_active,
  track_finished_inventory
)
select
  mi.id,
  w.sku,
  'Regular',
  w.price,
  true,
  true,
  false
from wanted w
join public.menu_categories mc on mc.name = w.category_name
join lateral (
  select id
  from public.menu_items
  where name = w.name
    and category_id = mc.id
  order by created_at desc
  limit 1
) mi on true
on conflict (sku) do update set
  price = excluded.price,
  is_active = true;


-- Development inventory data used by the Flutter inventory screen.
with desired(sku,name,category_name,uom_code,reorder_level,track_expiry,qty,expiry_days,unit_cost) as (
  values
    ('INV-001','Bottled Water','Finished Goods','pc',10::numeric,false,24::numeric,null::int,18::numeric),
    ('INV-002','Coca-Cola','Finished Goods','pc',8::numeric,false,18::numeric,null::int,28::numeric),
    ('INV-006','Chocolate Cake','Finished Goods','pc',3::numeric,true,2::numeric,2,90::numeric)
)
insert into public.inventory_items(
  sku,name,category_id,base_uom_id,track_inventory,track_expiry,
  allow_negative_stock,reorder_level,is_active
)
select
  d.sku,d.name,ic.id,u.id,true,d.track_expiry,false,d.reorder_level,true
from desired d
join public.inventory_categories ic on ic.name=d.category_name
join public.units_of_measure u on u.code=d.uom_code
on conflict (sku) do update set
  name=excluded.name,
  category_id=excluded.category_id,
  base_uom_id=excluded.base_uom_id,
  track_inventory=true,
  track_expiry=excluded.track_expiry,
  reorder_level=excluded.reorder_level,
  is_active=true;

with desired(sku,qty,expiry_days,unit_cost) as (
  values
    ('INV-001',24::numeric,null::int,18::numeric),
    ('INV-002',18::numeric,null::int,28::numeric),
    ('INV-006',2::numeric,2,90::numeric)
),
created_lots as (
  insert into public.inventory_lots(
    inventory_item_id,lot_code,received_at,expiration_date,
    received_quantity,remaining_quantity,unit_cost_base,status
  )
  select
    ii.id,
    'SEED-' || d.sku,
    now(),
    case when d.expiry_days is null then null else current_date + d.expiry_days end,
    d.qty,
    d.qty,
    d.unit_cost,
    'AVAILABLE'
  from desired d
  join public.inventory_items ii on ii.sku=d.sku
  where not exists (
    select 1 from public.stock_movements sm
    where sm.inventory_item_id=ii.id
  )
  returning id,inventory_item_id,received_quantity,unit_cost_base
)
insert into public.stock_movements(
  inventory_item_id,inventory_lot_id,movement_type,quantity_delta,
  unit_cost_base,reference_type,reason
)
select
  inventory_item_id,id,'MANUAL_IN',received_quantity,
  unit_cost_base,'SEED','Development seed opening stock'
from created_lots;


-- Ensure development sellable finished goods are linked after inventory rows exist.
update public.menu_variants mv
set
  track_finished_inventory = true,
  finished_inventory_item_id = ii.id,
  name = case
    when mv.sku = 'PRD-008' then '330 ml Can'
    else mv.name
  end
from public.inventory_items ii
where (
    (mv.sku = 'PRD-005' and ii.sku = 'INV-001')
    or
    (mv.sku = 'PRD-006' and ii.sku = 'INV-006')
    or
    (mv.sku = 'PRD-008' and ii.sku = 'INV-002')
  );
