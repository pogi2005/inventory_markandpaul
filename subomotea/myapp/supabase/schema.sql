create table if not exists public.products (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  price numeric(12, 2) not null check (price > 0),
  stock integer not null check (stock >= 0),
  created_at timestamptz not null default pg_catalog.now(),
  primary key (owner_id, id)
);

create table if not exists public.sales (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  product_id text not null,
  product_name text not null,
  unit_price numeric(12, 2) not null check (unit_price > 0),
  quantity integer not null check (quantity > 0),
  amount numeric generated always as (unit_price * quantity) stored,
  timestamp timestamptz not null,
  payment_method text,
  payment_id text,
  primary key (owner_id, id)
);

create index if not exists sales_owner_timestamp_idx
  on public.sales (owner_id, timestamp desc);

create table if not exists public.payment_logs (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  method text not null,
  amount numeric(12, 2) not null check (amount >= 0),
  status text not null check (status in ('paid', 'failed', 'pending')),
  items jsonb not null default '[]'::jsonb,
  item_count integer not null check (item_count >= 0),
  mode text not null default 'test',
  note text,
  client_time timestamptz,
  currency text not null default 'PHP',
  xendit_invoice_id text,
  invoice_url text,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (owner_id, id)
);

alter table public.payment_logs
  add column if not exists currency text not null default 'PHP',
  add column if not exists xendit_invoice_id text,
  add column if not exists invoice_url text;

create table if not exists public.app_state (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  reset_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now()
);

alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.payment_logs enable row level security;
alter table public.app_state enable row level security;

drop policy if exists products_owner_all on public.products;
create policy products_owner_all on public.products
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists sales_owner_all on public.sales;
create policy sales_owner_all on public.sales
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

drop policy if exists payment_logs_owner_all on public.payment_logs;
drop policy if exists payment_logs_owner_select on public.payment_logs;
create policy payment_logs_owner_select on public.payment_logs
  for select to authenticated
  using ((select auth.uid()) = owner_id);

drop policy if exists app_state_owner_all on public.app_state;
create policy app_state_owner_all on public.app_state
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, insert, update, delete on public.sales to authenticated;
revoke insert, update, delete on public.payment_logs from anon, authenticated;
grant select on public.payment_logs to authenticated;
grant select, insert, update, delete on public.app_state to authenticated;

create unique index if not exists payment_logs_id_uidx
  on public.payment_logs (id);

create or replace function public.record_sale(
  p_items jsonb,
  p_payment_method text default null,
  p_payment_id text default null
)
returns setof public.sales
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item jsonb;
  v_product public.products%rowtype;
  v_sale public.sales%rowtype;
  v_quantity integer;
begin
  if auth.uid() is null then
    raise exception 'Sign-in required';
  end if;

  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Sale must contain at least one item';
  end if;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(p_items) as items(value)
  loop
    if (v_item->>'product_id') is null
       or (v_item->>'quantity') is null
       or (v_item->>'quantity') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid sale item';
    end if;

    v_quantity := (v_item->>'quantity')::integer;

    select * into v_product
    from public.products
    where owner_id = auth.uid() and id = v_item->>'product_id'
    for update;

    if not found then
      raise exception 'Product no longer exists';
    end if;

    if v_quantity > v_product.stock then
      raise exception 'Not enough stock for % (only % left)',
        v_product.name, v_product.stock;
    end if;

    update public.products
    set stock = stock - v_quantity
    where owner_id = auth.uid() and id = v_product.id;

    insert into public.sales (
      owner_id, id, product_id, product_name, unit_price, quantity,
      timestamp, payment_method, payment_id
    ) values (
      auth.uid(), 'sale_' || pg_catalog.gen_random_uuid()::text,
      v_product.id, v_product.name, v_product.price, v_quantity,
      pg_catalog.now(), p_payment_method, p_payment_id
    ) returning * into v_sale;

    return next v_sale;
  end loop;

  return;
end;
$$;

revoke all on function public.record_sale(jsonb, text, text)
  from public, anon, authenticated;

create or replace function public.reserve_xendit_payment(
  p_owner_id uuid,
  p_payment_id text,
  p_items jsonb,
  p_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_product public.products%rowtype;
  v_quantity integer;
  v_total numeric(12, 2) := 0;
  v_count integer := 0;
  v_reserved_items jsonb := '[]'::jsonb;
begin
  if p_owner_id is null or p_payment_id is null or p_payment_id = '' then
    raise exception 'Invalid payment';
  end if;

  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array'
     or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Sale must contain at least one item';
  end if;

  for v_item in
    select value from pg_catalog.jsonb_array_elements(p_items) as items(value)
  loop
    if (v_item->>'product_id') is null
       or (v_item->>'quantity') is null
       or (v_item->>'quantity') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid sale item';
    end if;

    v_quantity := (v_item->>'quantity')::integer;

    select * into v_product
    from public.products
    where owner_id = p_owner_id and id = v_item->>'product_id'
    for update;

    if not found then
      raise exception 'Product no longer exists';
    end if;

    if v_quantity > v_product.stock then
      raise exception 'Not enough stock for % (only % left)',
        v_product.name, v_product.stock;
    end if;

    update public.products
    set stock = stock - v_quantity
    where owner_id = p_owner_id and id = v_product.id;

    v_total := v_total + v_product.price * v_quantity;
    v_count := v_count + v_quantity;
    v_reserved_items := v_reserved_items || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'product_id', v_product.id,
        'product_name', v_product.name,
        'unit_price', v_product.price,
        'quantity', v_quantity
      )
    );
  end loop;

  insert into public.payment_logs (
    owner_id, id, method, amount, status, items, item_count, mode, currency
  ) values (
    p_owner_id, p_payment_id, 'Xendit', v_total, 'pending',
    v_reserved_items, v_count, p_mode, 'PHP'
  );

  return pg_catalog.jsonb_build_object(
    'payment_id', p_payment_id,
    'amount', v_total,
    'items', v_reserved_items
  );
end;
$$;

create or replace function public.finish_xendit_payment(
  p_payment_id text,
  p_invoice_id text,
  p_status text,
  p_paid_amount numeric,
  p_currency text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payment_logs%rowtype;
  v_item jsonb;
  v_quantity integer;
begin
  select * into v_payment
  from public.payment_logs
  where id = p_payment_id
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  if v_payment.status <> 'pending' then
    return v_payment.status;
  end if;

  if p_status in ('PAID', 'SETTLED') then
    if p_currency <> v_payment.currency
       or p_paid_amount < v_payment.amount then
      raise exception 'Payment amount or currency does not match';
    end if;

    update public.payment_logs
    set status = 'paid', xendit_invoice_id = p_invoice_id
    where owner_id = v_payment.owner_id and id = v_payment.id;

    for v_item in
      select value
      from pg_catalog.jsonb_array_elements(v_payment.items) as items(value)
    loop
      v_quantity := (v_item->>'quantity')::integer;

      insert into public.sales (
        owner_id, id, product_id, product_name, unit_price, quantity,
        timestamp, payment_method, payment_id
      ) values (
        v_payment.owner_id,
        'sale_' || pg_catalog.gen_random_uuid()::text,
        v_item->>'product_id',
        v_item->>'product_name',
        (v_item->>'unit_price')::numeric,
        v_quantity,
        pg_catalog.now(),
        'Xendit',
        v_payment.id
      );
    end loop;

    return 'paid';
  end if;

  if p_status in ('EXPIRED', 'FAILED') then
    update public.payment_logs
    set status = 'failed', xendit_invoice_id = p_invoice_id
    where owner_id = v_payment.owner_id and id = v_payment.id;

    for v_item in
      select value
      from pg_catalog.jsonb_array_elements(v_payment.items) as items(value)
    loop
      v_quantity := (v_item->>'quantity')::integer;

      update public.products
      set stock = stock + v_quantity
      where owner_id = v_payment.owner_id and id = v_item->>'product_id';
    end loop;

    return 'failed';
  end if;

  return 'pending';
end;
$$;

revoke all on function public.reserve_xendit_payment(uuid, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function public.finish_xendit_payment(text, text, text, numeric, text)
  from public, anon, authenticated;

grant execute on function public.reserve_xendit_payment(uuid, text, jsonb, text)
  to service_role;
grant execute on function public.finish_xendit_payment(text, text, text, numeric, text)
  to service_role;