# Database (Supabase)

`migrations/` holds the SQL that builds the database. Files are applied in name order.

| File | What it does |
|---|---|
| `20261111000000_step1_schema.sql` | Tables, data rules, security rules (RLS), first-sign-in setup (`bootstrap_household`) |

## Apply to your Supabase project
1. Supabase dashboard > **SQL Editor** > **New query**.
2. Paste the whole migration file and press **Run**. (A warning about "destructive operations" can appear because the file contains `revoke`; confirm.)
3. It must say "Success". Run it **only once**.

## Security model in one paragraph
Every row belongs to a household. A signed-in user only ever sees their own household. **Admins** can do everything in it.
**Members** are read-only and only receive *shared expense* items: no income, no savings, no balances, no accounts, no private items.
This is enforced inside the database (Row Level Security), not only in the app. The public `anon` key has no table access at all.

## Test the rules locally (needs PostgreSQL 14+ installed)
```bash
bash supabase/tests/run_local.sh
```
This builds a throw-away database, applies every migration and runs `tests/rls_test.sql`
(about 60 checks: household isolation, member read-only, shared/private, month lock, transfers, last-admin guard).
The same test runs automatically in GitHub Actions (job `database`).

## Default category keys
Default categories are stored with a `name_key` and no `name`; the app shows the translation for the user's language.
Keys: salary_me, salary_other, other_income, refund_gift, rent, phone_bill, childcare, installments,
internet_electricity, money_to_family, loan_payments, groceries_essentials, medicine, doctor, kids_needs,
transport, other_essential, groceries_treats, eating_out, physio, family_clothes, parties_gifts,
events_gifts_abroad, celebrations_outings, entertainment, other_optional, transfer.
All start **private**.
