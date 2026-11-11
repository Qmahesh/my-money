-- Automated checks for the Step 1 database rules.
-- Run with:  bash supabase/tests/run_local.sh
\set ON_ERROR_STOP on
\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'
\set carol '33333333-3333-3333-3333-333333333333'
\set dave  '44444444-4444-4444-4444-444444444444'

-- ---------- test helpers (run with the privileges of whoever calls them) ----------
create schema t;
grant usage on schema t to authenticated, anon;

-- Runs a statement that MUST fail with the given SQLSTATE.
create function t.expect_fail(stmt text, expected_state text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate = expected_state then
      return;
    end if;
    raise exception 'Wrong error for [%]: got % (%), expected %', stmt, sqlstate, sqlerrm, expected_state;
  end;
  raise exception 'Statement should have failed but succeeded: %', stmt;
end $$;

-- Runs a statement and checks how many rows it changed.
create function t.expect_rows(stmt text, expected bigint) returns void
language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  if n <> expected then
    raise exception 'Expected % row(s) for [%], got %', expected, stmt, n;
  end if;
end $$;

create function t.check(cond boolean, label text) returns void
language plpgsql as $$
begin
  if cond is not true then
    raise exception 'CHECK FAILED: %', label;
  end if;
  raise notice 'ok   %', label;
end $$;

grant execute on all functions in schema t to authenticated, anon;

-- ---------- users ----------
insert into auth.users (id, email) values
  (:'alice', 'alice@example.com'), (:'bob', 'bob@example.com'),
  (:'carol', 'carol@example.com'), (:'dave', 'dave@example.com');

-- ======================= ALICE: creates household A =======================
set role authenticated;
select set_config('request.jwt.claim.sub', :'alice', false);

select public.bootstrap_household('Alice home', 'SEK', 'en') as hid_a \gset
select t.check(:'hid_a' is not null, 'bootstrap creates household for first sign-in');
select t.check(public.bootstrap_household('Other name', 'SEK', 'en') = :'hid_a'::uuid, 'bootstrap is idempotent');
select t.check((select count(*) from public.households) = 1, 'alice sees one household');
select t.check((select count(*) from public.accounts) = 1, 'default account created');
select t.check((select name from public.accounts) = 'Main account', 'default account name (en)');
select t.check((select count(*) from public.categories) = 27, '27 default categories seeded');
select t.check((select count(*) from public.categories where visibility = 'shared') = 0, 'all default categories start private');

select id as acct_sek from public.accounts limit 1 \gset
select id as cat_groc from public.categories where name_key = 'groceries_essentials' \gset
select id as cat_family from public.categories where name_key = 'money_to_family' \gset
select id as cat_treats from public.categories where name_key = 'groceries_treats' \gset
select id as cat_salary from public.categories where name_key = 'salary_me' \gset
select id as cat_rent from public.categories where name_key = 'rent' \gset
select id as cat_phone from public.categories where name_key = 'phone_bill' \gset

-- cannot share an income category
select t.expect_fail(format($$update public.categories set visibility = 'shared' where id = %L$$, :'cat_salary'), '23514');

-- share groceries, rent and phone categories
update public.categories set visibility = 'shared' where id in (:'cat_groc', :'cat_rent', :'cat_phone');

-- ---------- transactions ----------
insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount, note) values
  (:'hid_a', '2026-10-05', 'expense', :'cat_groc',   :'acct_sek', 640,   'T1 shared groceries'),
  (:'hid_a', '2026-10-06', 'expense', :'cat_family', :'acct_sek', 3000,  'T2 private family money'),
  (:'hid_a', '2026-10-07', 'expense', :'cat_family', :'acct_sek', 100,   'T3 private cat, override shared'),
  (:'hid_a', '2026-10-08', 'expense', :'cat_groc',   :'acct_sek', 50,    'T4 shared cat, override private'),
  (:'hid_a', '2026-10-09', 'income',  :'cat_salary', :'acct_sek', 32000, 'T5 salary'),
  (:'hid_a', '2026-10-10', 'expense', :'cat_groc',   :'acct_sek', 20,    'T6 deleted');
update public.transactions set visibility_override = 'shared'  where note like 'T3%';
update public.transactions set visibility_override = 'private' where note like 'T4%';
update public.transactions set deleted_at = now()              where note like 'T6%';

select t.check((select currency from public.transactions where note like 'T1%') = 'SEK', 'currency copied from account by trigger');
select t.check((select count(*) from public.transactions) = 6, 'admin sees all 6 transactions (incl. deleted)');

-- data rules
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-11', 'expense', %L, %L, 5)$$, :'hid_a', :'cat_salary', :'acct_sek'), '23514');   -- income category on expense
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-11', 'expense', %L, %L, 0)$$, :'hid_a', :'cat_groc', :'acct_sek'), '23514');     -- zero amount
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount, visibility_override)
  values (%L, '2026-10-11', 'income', %L, %L, 5, 'shared')$$, :'hid_a', :'cat_salary', :'acct_sek'), '23514'); -- shared income

-- ---------- second account (LKR, balance only) and transfers ----------
insert into public.accounts (household_id, name, currency, kind, tracking, sort_order)
  values (:'hid_a', 'LK Savings', 'LKR', 'savings', 'balance_only', 2),
         (:'hid_a', 'SE Savings', 'SEK', 'savings', 'detailed', 3);
select id as acct_lkr from public.accounts where name = 'LK Savings' \gset
select id as acct_sav from public.accounts where name = 'SE Savings' \gset

insert into public.transfers (household_id, occurred_on, from_account_id, to_account_id, sent_amount, received_amount)
  values (:'hid_a', '2026-10-12', :'acct_sek', :'acct_lkr', 3000, 93750);                  -- cross currency, different amounts: ok
insert into public.transfers (household_id, occurred_on, from_account_id, to_account_id, sent_amount, received_amount)
  values (:'hid_a', '2026-10-12', :'acct_sek', :'acct_sav', 5000, 5000);                   -- same currency, equal: ok
select t.expect_fail(format($$insert into public.transfers (household_id, occurred_on, from_account_id, to_account_id, sent_amount, received_amount)
  values (%L, '2026-10-12', %L, %L, 5000, 4000)$$, :'hid_a', :'acct_sek', :'acct_sav'), '23514'); -- same currency, unequal
select t.expect_fail(format($$insert into public.transfers (household_id, occurred_on, from_account_id, to_account_id, sent_amount, received_amount)
  values (%L, '2026-10-12', %L, %L, 5, 5)$$, :'hid_a', :'acct_sek', :'acct_sek'), '23514');   -- same account

-- ---------- recurring items ----------
insert into public.recurring_templates (household_id, name, kind, category_id, account_id, due_day, active_from)
  values (:'hid_a', 'Rent', 'bill', :'cat_rent', :'acct_sek', 28, '2026-10-01');
select id as tpl_rent from public.recurring_templates where name = 'Rent' \gset
insert into public.recurring_amounts (household_id, template_id, effective_from, amount)
  values (:'hid_a', :'tpl_rent', '2026-10-01', 6000), (:'hid_a', :'tpl_rent', '2027-01-01', 8000);
insert into public.recurring_instances (household_id, template_id, month) values (:'hid_a', :'tpl_rent', '2026-10-01');

insert into public.recurring_templates (household_id, name, kind, category_id, account_id, due_day, active_from)
  values (:'hid_a', 'Salary', 'income', :'cat_salary', :'acct_sek', 25, '2026-10-01');
insert into public.recurring_templates (household_id, name, kind, category_id, account_id, due_day, active_from)
  values (:'hid_a', 'Family money', 'bill', :'cat_family', :'acct_sek', 5, '2026-10-01');

select t.expect_fail(format($$insert into public.recurring_amounts (household_id, template_id, effective_from, amount)
  values (%L, %L, '2027-01-15', 9000)$$, :'hid_a', :'tpl_rent'), '23514');                   -- not first of month
select t.expect_fail(format($$insert into public.recurring_templates (household_id, name, kind, category_id, account_id, active_from)
  values (%L, 'Bad', 'bill', %L, %L, '2026-10-01')$$, :'hid_a', :'cat_salary', :'acct_sek'), '23514'); -- bill with income category

-- ---------- month lock ----------
insert into public.month_locks (household_id, month) values (:'hid_a', '2026-09-01');
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-09-15', 'expense', %L, %L, 10)$$, :'hid_a', :'cat_groc', :'acct_sek'), '23514');  -- add into locked month
insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount, note)
  values (:'hid_a', '2026-10-15', 'expense', :'cat_groc', :'acct_sek', 10, 'T7 october');
select t.expect_fail(format($$update public.transactions set occurred_on = '2026-09-20' where note like 'T7%%'$$), '23514'); -- move into locked month
select t.expect_fail(format($$insert into public.transfers (household_id, occurred_on, from_account_id, to_account_id, sent_amount, received_amount)
  values (%L, '2026-09-12', %L, %L, 5, 5)$$, :'hid_a', :'acct_sek', :'acct_sav'), '23514');         -- transfer in locked month
select t.expect_fail(format($$insert into public.balance_updates (household_id, account_id, as_of, balance)
  values (%L, %L, '2026-09-30', 100)$$, :'hid_a', :'acct_lkr'), '23514');                           -- balance update in locked month
-- unlock, add a row in September, lock again, then try to soft-delete it
delete from public.month_locks where month = '2026-09-01';
insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount, note)
  values (:'hid_a', '2026-09-15', 'expense', :'cat_groc', :'acct_sek', 10, 'T8 september');
insert into public.month_locks (household_id, month) values (:'hid_a', '2026-09-01');
select t.expect_fail(format($$update public.transactions set deleted_at = now() where note like 'T8%%'$$), '23514'); -- delete in locked month
select t.expect_fail(format($$delete from public.transactions where note like 'T8%%'$$), '23514');
delete from public.month_locks where month = '2026-09-01';
select t.check(true, 'month lock blocks add / move / delete / transfers / balance updates; unlock reopens');

-- balance update outside locked month works
insert into public.balance_updates (household_id, account_id, as_of, balance) values (:'hid_a', :'acct_lkr', '2026-10-31', 250000);

-- last-admin guard
select t.expect_fail(format($$delete from public.household_members where user_id = %L$$, :'alice'), '23514');
select t.expect_fail(format($$update public.household_members set role = 'member' where user_id = %L$$, :'alice'), '23514');
select t.check(true, 'last admin cannot be removed or demoted');

-- ======================= invite Bob as a member (done by the system for now) =======================
reset role;
insert into public.household_members (household_id, user_id, role) values (:'hid_a', :'bob', 'member');

-- ======================= BOB: member, view only, shared expenses only =======================
set role authenticated;
select set_config('request.jwt.claim.sub', :'bob', false);

select t.check((select count(*) from public.households) = 1, 'member sees own household');
select t.check((select count(*) from public.household_members) = 1, 'member sees only their own membership row');
select t.check((select count(*) from public.accounts) = 0, 'member sees NO accounts');
select t.check((select count(*) from public.balance_updates) = 0, 'member sees NO balances');
select t.check((select count(*) from public.transfers) = 0, 'member sees NO transfers');
select t.check((select count(*) from public.month_locks) = 0, 'member sees no month locks');
select t.check((select count(*) from public.categories) = 3, 'member sees only the 3 shared expense categories');
select t.check((select count(*) from public.categories where kind <> 'expense') = 0, 'member sees no income/transfer categories');

select t.check((select count(*) from public.transactions) = 4, 'member sees exactly 4 transactions (T1, T3, T7, T8)');
select t.check((select count(*) from public.transactions where note like 'T2%' or note like 'T4%' or note like 'T5%' or note like 'T6%') = 0,
  'member does not see private category, private override, income or deleted rows');
select t.check((select count(*) from public.transactions where note like 'T3%') = 1, 'override=shared on a private category is visible');
select t.check((select count(*) from public.recurring_templates) = 1, 'member sees only the shared bill template (not income, not private bill)');
select t.check((select count(*) from public.recurring_amounts) = 2, 'member sees amounts of the shared bill');
select t.check((select count(*) from public.recurring_instances) = 1, 'member sees instances of the shared bill');

-- read-only
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-20', 'expense', %L, %L, 1)$$, :'hid_a', :'cat_groc', :'acct_sek'), '42501');
select t.expect_rows($$update public.transactions set amount = 1$$, 0);
select t.expect_rows($$delete from public.transactions$$, 0);
select t.expect_rows($$update public.categories set visibility = 'private'$$, 0);
select t.expect_rows($$update public.household_members set role = 'admin'$$, 0);
select t.expect_rows($$update public.households set name = 'Hacked'$$, 0);
select t.expect_fail(format($$insert into public.accounts (household_id, name, currency, kind) values (%L, 'x', 'SEK', 'spending')$$, :'hid_a'), '42501');
select t.expect_fail(format($$insert into public.household_members (household_id, user_id, role) values (%L, %L, 'admin')$$, :'hid_a', :'bob'), '42501');
select t.expect_fail(format($$insert into public.month_locks (household_id, month) values (%L, '2026-08-01')$$, :'hid_a'), '42501');
select t.check(true, 'member cannot add, change or delete anything');

-- ======================= CAROL: another household =======================
select set_config('request.jwt.claim.sub', :'carol', false);
select public.bootstrap_household('Carol home', 'EUR', 'sv') as hid_b \gset
select t.check(:'hid_b' <> :'hid_a', 'carol gets her own household');
select t.check((select name from public.accounts) = 'Huvudkonto', 'default account name (sv)');
select t.check((select currency from public.accounts) = 'EUR', 'household currency respected');
select t.check((select count(*) from public.transactions) = 0, 'carol sees none of household A transactions');
select t.check((select count(*) from public.accounts where id = :'acct_sek') = 0, 'carol cannot see household A accounts');
select t.check((select count(*) from public.households) = 1, 'carol sees only her household');

select id as cat_b from public.categories where name_key = 'groceries_essentials' \gset
select id as acct_b from public.accounts limit 1 \gset
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-20', 'expense', %L, %L, 1)$$, :'hid_a', :'cat_groc', :'acct_sek'), '42501');                -- write into household A
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-20', 'expense', %L, %L, 1)$$, :'hid_b', :'cat_b', :'acct_sek'), '23503');                  -- own household, A's account
select t.expect_fail(format($$insert into public.transactions (household_id, occurred_on, kind, category_id, account_id, amount)
  values (%L, '2026-10-20', 'expense', %L, %L, 1)$$, :'hid_b', :'cat_groc', :'acct_b'), '23503');                 -- own household, A's category
select t.expect_rows(format($$update public.categories set visibility = 'shared' where id = %L$$, :'cat_groc'), 0);
select t.expect_rows(format($$delete from public.accounts where id = %L$$, :'acct_sek'), 0);
select t.expect_fail($$insert into public.households (name) values ('sneaky')$$, '42501');
select t.check(true, 'household B cannot read or write household A data');

-- ======================= DAVE: signed in, no household yet =======================
select set_config('request.jwt.claim.sub', :'dave', false);
select t.check(public.current_household_id() is null, 'user without household has no household id');
select t.check((select count(*) from public.transactions) = 0 and (select count(*) from public.accounts) = 0 and (select count(*) from public.households) = 0,
  'user without household sees nothing');
select t.check(public.is_admin() is false, 'user without household is not admin');

-- ======================= NOT SIGNED IN =======================
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select t.expect_fail($$select count(*) from public.transactions$$, '42501');
select t.expect_fail($$select public.bootstrap_household()$$, '42501');
reset role;
set role authenticated;
select t.expect_fail($$select public.bootstrap_household()$$, '28000');
select t.check(true, 'anonymous key has no table access; bootstrap needs a signed-in user');

-- ======================= final state check as superuser =======================
reset role;
select t.check((select role from public.household_members where user_id = :'bob') = 'member', 'bob is still a member after escalation attempts');
select t.check((select name from public.households where id = :'hid_a') = 'Alice home', 'household A name untouched');
select t.check((select count(*) from public.transactions where household_id = :'hid_b') = 0, 'nothing leaked into household B');

\echo ALL DATABASE CHECKS PASSED
