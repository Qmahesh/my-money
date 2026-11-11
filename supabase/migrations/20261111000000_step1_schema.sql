-- =====================================================================
-- My Money - Step 1: database schema, security rules (RLS), helpers
-- Run ONCE in Supabase: SQL Editor > New query > paste all > Run.
--
-- Design (see docs/PROJECT_SPEC.md):
--   * Multi-tenant: every row belongs to a household (household_id).
--   * Roles: admin (can edit everything) and member (view only).
--   * Members only ever see SHARED EXPENSE items. Income, savings,
--     balances, accounts, private items are never visible to them.
--   * Amounts are stored in the ACCOUNT's own currency. No exchange
--     rates are stored.
--   * Months can be locked; locked months cannot be changed.
--   * Deleting = soft delete (deleted_at) so it can be undone.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------
create or replace function public.month_start(d date)
returns date language sql immutable as $$
  select date_trunc('month', d)::date
$$;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table public.households (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(trim(name)) between 1 and 80),
  base_currency text not null default 'SEK' check (base_currency ~ '^[A-Z]{3}$'),
  created_at    timestamptz not null default now()
);

-- One user belongs to exactly one household (unique user_id).
create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null check (role in ('admin', 'member')),
  created_at   timestamptz not null default now(),
  primary key (household_id, user_id),
  unique (user_id)
);

create table public.accounts (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  name            text not null check (length(trim(name)) between 1 and 60),
  currency        text not null check (currency ~ '^[A-Z]{3}$'),
  kind            text not null check (kind in ('spending', 'savings')),
  -- detailed: balance is calculated from entries; balance_only: you enter month-end balances
  tracking        text not null default 'detailed' check (tracking in ('detailed', 'balance_only')),
  opening_balance numeric(14,2) not null default 0,
  sort_order      int  not null default 0,   -- lowest = default account
  is_archived     boolean not null default false,
  created_at      timestamptz not null default now(),
  unique (id, household_id),
  unique (household_id, name)
);

-- name is NULL for untouched default categories: the app then shows the
-- translation of name_key in the user's language.
create table public.categories (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  name           text check (name is null or length(trim(name)) between 1 and 60),
  name_key       text,
  kind           text not null check (kind in ('income', 'expense', 'transfer')),
  necessity      text not null check (necessity in ('income', 'fixed', 'essential', 'optional', 'transfer')),
  visibility     text not null default 'private' check (visibility in ('private', 'shared')),
  monthly_budget numeric(14,2) check (monthly_budget is null or monthly_budget >= 0),
  sort_order     int not null default 0,
  is_archived    boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (id, household_id),
  check (name is not null or name_key is not null),
  check (
    (kind = 'income'   and necessity = 'income') or
    (kind = 'transfer' and necessity = 'transfer') or
    (kind = 'expense'  and necessity in ('fixed', 'essential', 'optional'))
  ),
  -- only expenses can be shared with members
  check (visibility = 'private' or kind = 'expense')
);

create table public.transactions (
  id                  uuid primary key default gen_random_uuid(),
  household_id        uuid not null references public.households(id) on delete cascade,
  occurred_on         date not null,
  kind                text not null check (kind in ('income', 'expense')),
  category_id         uuid not null,
  account_id          uuid not null,
  amount              numeric(14,2) not null check (amount > 0),
  currency            text not null,            -- filled automatically from the account
  note                text check (note is null or length(note) <= 300),
  visibility_override text check (visibility_override in ('private', 'shared')),
  created_by          uuid default auth.uid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  unique (id, household_id),
  foreign key (category_id, household_id) references public.categories(id, household_id),
  foreign key (account_id,  household_id) references public.accounts(id,  household_id),
  check (visibility_override is null or kind = 'expense' or visibility_override = 'private')
);

-- Moving money between your own accounts. Never income or expense.
create table public.transfers (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.households(id) on delete cascade,
  occurred_on      date not null,
  from_account_id  uuid not null,
  to_account_id    uuid not null,
  sent_amount      numeric(14,2) not null check (sent_amount > 0),      -- in from-account currency
  received_amount  numeric(14,2) not null check (received_amount > 0),  -- in to-account currency
  note             text check (note is null or length(note) <= 300),
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (id, household_id),
  foreign key (from_account_id, household_id) references public.accounts(id, household_id),
  foreign key (to_account_id,   household_id) references public.accounts(id, household_id),
  check (from_account_id <> to_account_id)
);

-- Monthly bills and expected income (rent, phone bill, salary ...)
create table public.recurring_templates (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name         text not null check (length(trim(name)) between 1 and 80),
  kind         text not null check (kind in ('bill', 'income')),
  category_id  uuid not null,
  account_id   uuid not null,
  due_day      int  not null default 1 check (due_day between 1 and 31),
  active_from  date not null check (active_from = date_trunc('month', active_from)::date),
  active_until date check (active_until is null or
                           (active_until = date_trunc('month', active_until)::date and active_until >= active_from)),
  is_archived  boolean not null default false,
  created_at   timestamptz not null default now(),
  unique (id, household_id),
  foreign key (category_id, household_id) references public.categories(id, household_id),
  foreign key (account_id,  household_id) references public.accounts(id,  household_id)
);

-- Amount history: rent 6000 from Oct 2026, 8000 from Jan 2027 ...
create table public.recurring_amounts (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  template_id    uuid not null,
  effective_from date not null check (effective_from = date_trunc('month', effective_from)::date),
  amount         numeric(14,2) not null check (amount > 0),
  unique (template_id, effective_from),
  foreign key (template_id, household_id) references public.recurring_templates(id, household_id) on delete cascade
);

-- One row per template per month: pending until ticked.
create table public.recurring_instances (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  template_id    uuid not null,
  month          date not null check (month = date_trunc('month', month)::date),
  status         text not null default 'pending' check (status in ('pending', 'done')),
  actual_amount  numeric(14,2) check (actual_amount is null or actual_amount >= 0),
  done_on        date,
  transaction_id uuid,
  unique (template_id, month),
  foreign key (template_id,    household_id) references public.recurring_templates(id, household_id) on delete cascade,
  foreign key (transaction_id, household_id) references public.transactions(id, household_id)
);

-- "On this date the real balance was X" (month-end balances, Sri Lanka accounts ...)
create table public.balance_updates (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  account_id   uuid not null,
  as_of        date not null,
  balance      numeric(14,2) not null,
  note         text check (note is null or length(note) <= 300),
  created_at   timestamptz not null default now(),
  foreign key (account_id, household_id) references public.accounts(id, household_id)
);

create table public.month_locks (
  household_id uuid not null references public.households(id) on delete cascade,
  month        date not null check (month = date_trunc('month', month)::date),
  locked_at    timestamptz not null default now(),
  locked_by    uuid default auth.uid(),
  primary key (household_id, month)
);

-- Indexes for the screens we will build
create index transactions_household_date_idx on public.transactions (household_id, occurred_on);
create index transactions_household_category_idx on public.transactions (household_id, category_id);
create index transfers_household_date_idx on public.transfers (household_id, occurred_on);
create index recurring_instances_household_month_idx on public.recurring_instances (household_id, month);
create index balance_updates_account_date_idx on public.balance_updates (account_id, as_of);

-- ---------------------------------------------------------------------
-- Helper functions used by the security rules.
-- SECURITY DEFINER so that they can read membership without recursion.
-- ---------------------------------------------------------------------
create or replace function public.current_household_id()
returns uuid language sql stable security definer set search_path = public as $$
  select household_id from public.household_members where user_id = auth.uid() limit 1
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.household_members where user_id = auth.uid() and role = 'admin'
  )
$$;

create or replace function public.category_visibility(cat uuid)
returns text language sql stable security definer set search_path = public as $$
  select visibility from public.categories
  where id = cat and household_id = public.current_household_id()
$$;

create or replace function public.template_is_shared(tpl uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.recurring_templates t
    where t.id = tpl
      and t.household_id = public.current_household_id()
      and t.kind = 'bill'
      and not t.is_archived
      and public.category_visibility(t.category_id) = 'shared'
  )
$$;

create or replace function public.is_month_locked(h uuid, d date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.month_locks where household_id = h and month = public.month_start(d)
  )
$$;

-- ---------------------------------------------------------------------
-- Trigger functions (data rules that must always hold)
-- ---------------------------------------------------------------------
create or replace function public.tg_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Transaction: category kind must match, currency is copied from the account.
create or replace function public.tg_transaction_checks()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cat_kind text;
  acct_currency text;
begin
  select kind into cat_kind from public.categories where id = new.category_id;
  if cat_kind is distinct from new.kind then
    raise exception 'Category type (%) does not match the transaction type (%)', cat_kind, new.kind
      using errcode = 'check_violation';
  end if;
  select currency into acct_currency from public.accounts where id = new.account_id;
  new.currency := acct_currency;
  return new;
end $$;

-- Transfer: same-currency transfers must send and receive the same amount.
create or replace function public.tg_transfer_checks()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  from_cur text;
  to_cur text;
begin
  select currency into from_cur from public.accounts where id = new.from_account_id;
  select currency into to_cur   from public.accounts where id = new.to_account_id;
  if from_cur = to_cur and new.sent_amount <> new.received_amount then
    raise exception 'A transfer between accounts with the same currency must send and receive the same amount'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- Recurring template: bills use expense categories, income uses income categories.
create or replace function public.tg_template_checks()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cat_kind text;
begin
  select kind into cat_kind from public.categories where id = new.category_id;
  if (new.kind = 'bill' and cat_kind is distinct from 'expense')
     or (new.kind = 'income' and cat_kind is distinct from 'income') then
    raise exception 'Category type does not match the recurring item type'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- Month lock: nothing in a locked month can be added, changed or removed.
-- The date column to inspect is passed as the trigger argument.
create or replace function public.tg_enforce_month_lock()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  col text := tg_argv[0];
  d date;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    d := (to_jsonb(old) ->> col)::date;
    if public.is_month_locked(old.household_id, d) then
      raise exception 'The month % is locked', to_char(d, 'YYYY-MM') using errcode = 'check_violation';
    end if;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    d := (to_jsonb(new) ->> col)::date;
    if public.is_month_locked(new.household_id, d) then
      raise exception 'The month % is locked', to_char(d, 'YYYY-MM') using errcode = 'check_violation';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

-- A household must always keep at least one admin.
create or replace function public.tg_guard_last_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'admin'
     and (tg_op = 'DELETE' or new.role <> 'admin')
     and exists (select 1 from public.households where id = old.household_id)
     and not exists (
       select 1 from public.household_members
       where household_id = old.household_id and role = 'admin' and user_id <> old.user_id
     ) then
    raise exception 'A household must keep at least one admin' using errcode = 'check_violation';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

create trigger transactions_checks before insert or update on public.transactions
  for each row execute function public.tg_transaction_checks();
create trigger transactions_touch before update on public.transactions
  for each row execute function public.tg_touch_updated_at();
create trigger transactions_lock before insert or update or delete on public.transactions
  for each row execute function public.tg_enforce_month_lock('occurred_on');

create trigger transfers_checks before insert or update on public.transfers
  for each row execute function public.tg_transfer_checks();
create trigger transfers_touch before update on public.transfers
  for each row execute function public.tg_touch_updated_at();
create trigger transfers_lock before insert or update or delete on public.transfers
  for each row execute function public.tg_enforce_month_lock('occurred_on');

create trigger templates_checks before insert or update on public.recurring_templates
  for each row execute function public.tg_template_checks();

create trigger instances_lock before insert or update or delete on public.recurring_instances
  for each row execute function public.tg_enforce_month_lock('month');

create trigger balance_updates_lock before insert or update or delete on public.balance_updates
  for each row execute function public.tg_enforce_month_lock('as_of');

create trigger members_guard_last_admin before update or delete on public.household_members
  for each row execute function public.tg_guard_last_admin();

-- ---------------------------------------------------------------------
-- Row Level Security: nobody can read or write anything unless a rule allows it
-- ---------------------------------------------------------------------
alter table public.households          enable row level security;
alter table public.household_members   enable row level security;

create policy households_select on public.households
  for select to authenticated
  using (id = public.current_household_id());

create policy households_update on public.households
  for update to authenticated
  using (id = public.current_household_id() and public.is_admin())
  with check (id = public.current_household_id() and public.is_admin());

create policy members_select on public.household_members
  for select to authenticated
  using (user_id = auth.uid()
         or (household_id = public.current_household_id() and public.is_admin()));

create policy members_update on public.household_members
  for update to authenticated
  using (household_id = public.current_household_id() and public.is_admin())
  with check (household_id = public.current_household_id() and public.is_admin());

create policy members_delete on public.household_members
  for delete to authenticated
  using (household_id = public.current_household_id() and public.is_admin());

-- Admins: full access to everything inside their own household.
do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'categories', 'transactions', 'transfers', 'recurring_templates',
    'recurring_amounts', 'recurring_instances', 'balance_updates', 'month_locks'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (household_id = public.current_household_id() and public.is_admin())
         with check (household_id = public.current_household_id() and public.is_admin())',
      t || '_admin_all', t);
  end loop;
end $$;

-- Members: READ ONLY, and only SHARED EXPENSE items.
create policy categories_member_select on public.categories
  for select to authenticated
  using (household_id = public.current_household_id()
         and kind = 'expense' and visibility = 'shared' and not is_archived);

create policy transactions_member_select on public.transactions
  for select to authenticated
  using (household_id = public.current_household_id()
         and deleted_at is null
         and kind = 'expense'
         and coalesce(visibility_override, public.category_visibility(category_id)) = 'shared');

create policy templates_member_select on public.recurring_templates
  for select to authenticated
  using (household_id = public.current_household_id() and public.template_is_shared(id));

create policy amounts_member_select on public.recurring_amounts
  for select to authenticated
  using (household_id = public.current_household_id() and public.template_is_shared(template_id));

create policy instances_member_select on public.recurring_instances
  for select to authenticated
  using (household_id = public.current_household_id() and public.template_is_shared(template_id));

-- ---------------------------------------------------------------------
-- Privileges: the public (anon) key can do nothing; signed-in users are
-- limited by the RLS rules above.
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.month_start(date),
  public.current_household_id(),
  public.is_admin(),
  public.category_visibility(uuid),
  public.template_is_shared(uuid),
  public.is_month_locked(uuid, date)
to authenticated;

-- ---------------------------------------------------------------------
-- First sign-in: create the user's household with default categories.
-- Call from the app after login:  select public.bootstrap_household('Our home', 'SEK', 'en');
-- Safe to call repeatedly: returns the existing household if there is one.
-- All default categories start PRIVATE; the admin decides what to share.
-- ---------------------------------------------------------------------
create or replace function public.bootstrap_household(
  p_name text default 'My household',
  p_currency text default 'SEK',
  p_language text default 'en'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  hid uuid;
  acct_name text;
begin
  if uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;

  select household_id into hid from public.household_members where user_id = uid;
  if hid is not null then
    return hid;
  end if;

  insert into public.households (name, base_currency)
  values (coalesce(nullif(trim(p_name), ''), 'My household'), upper(p_currency))
  returning id into hid;

  insert into public.household_members (household_id, user_id, role) values (hid, uid, 'admin');

  acct_name := case p_language when 'si' then 'ප්‍රධාන ගිණුම' when 'sv' then 'Huvudkonto' else 'Main account' end;
  insert into public.accounts (household_id, name, currency, kind, tracking, sort_order)
  values (hid, acct_name, upper(p_currency), 'spending', 'detailed', 1);

  insert into public.categories (household_id, name_key, kind, necessity, sort_order)
  select hid, v.k, v.kind, v.nec, v.ord
  from (values
    ('salary_me',              'income',   'income',    10),
    ('salary_other',           'income',   'income',    20),
    ('other_income',           'income',   'income',    30),
    ('refund_gift',            'income',   'income',    40),
    ('rent',                   'expense',  'fixed',    110),
    ('phone_bill',             'expense',  'fixed',    120),
    ('childcare',              'expense',  'fixed',    130),
    ('installments',           'expense',  'fixed',    140),
    ('internet_electricity',   'expense',  'fixed',    150),
    ('money_to_family',        'expense',  'fixed',    160),
    ('loan_payments',          'expense',  'fixed',    170),
    ('groceries_essentials',   'expense',  'essential', 210),
    ('medicine',               'expense',  'essential', 220),
    ('doctor',                 'expense',  'essential', 230),
    ('kids_needs',             'expense',  'essential', 240),
    ('transport',              'expense',  'essential', 250),
    ('other_essential',        'expense',  'essential', 260),
    ('groceries_treats',       'expense',  'optional',  310),
    ('eating_out',             'expense',  'optional',  320),
    ('physio',                 'expense',  'optional',  330),
    ('family_clothes',         'expense',  'optional',  340),
    ('parties_gifts',          'expense',  'optional',  350),
    ('events_gifts_abroad',    'expense',  'optional',  360),
    ('celebrations_outings',   'expense',  'optional',  370),
    ('entertainment',          'expense',  'optional',  380),
    ('other_optional',         'expense',  'optional',  390),
    ('transfer',               'transfer', 'transfer',  900)
  ) as v(k, kind, nec, ord);

  return hid;
exception
  when unique_violation then
    -- two calls at the same moment: use the household the other call created
    select household_id into hid from public.household_members where user_id = uid;
    return hid;
end $$;

revoke execute on function public.bootstrap_household(text, text, text) from public, anon;
grant execute on function public.bootstrap_household(text, text, text) to authenticated;
