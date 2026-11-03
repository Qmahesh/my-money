# Family Money Tracker (PWA) - Project Spec

Single source of truth. Paste this into any new chat/session so work continues without re-explaining.
Status: planning finished, build not started. Excel prototype (Family_Money_Tracker_v2.xlsx) exists and defines the data model.

## 1. Goal
Mobile-first web app (PWA) for personal/family income, expenses, bills and account balances.
Also a portfolio project: public GitHub repo + public demo for job applications in Sweden.
Everything must run on FREE tiers.

## 2. Tech stack
- Frontend: React + TypeScript (Vite), PWA (manifest, installable, offline shell). Mobile-first. Blue theme (NOT green).
- Backend: Supabase (Postgres, Auth, Row Level Security). Free plan.
- Hosting: Vercel or Cloudflare Pages (free).
- CI / jobs: GitHub Actions (free): daily keep-alive request, weekly encrypted DB backup.
- i18n: Sinhala (si), English (en), Svenska (sv). User picks language in the UI.
- Later option: package as Android app via Trusted Web Activity (PWABuilder/Bubblewrap). Not iOS App Store.

## 3. Architecture decisions (agreed)
- Multi-tenant: every row has household_id. RLS ensures users only see their household. Needed for family roles AND safe public demo.
- Roles per household: admin (can edit; several allowed), member (VIEW ONLY; up to ~3).
- Visibility: categories (and optionally single entries) are Private or Shared. DEFAULT = Private. Members see only Shared expense items. Members never receive income, savings, balances, private items (enforced in DB, not just UI).
- Real app: invite-only (sign-ups closed). Demo: separate Supabase project + separate deployment from the same code.
- Month = calendar month (1st to last day). Timezone Europe/Stockholm.
- Dates: any past date allowed (user enters history manually; NO Excel import).
- Month lock: admin can lock a month (no add/edit/delete/tick in it); admin can unlock.
- Delete = soft delete with "Recently deleted" + restore (undo). NO edit history / audit usernames.
- Search: all months; by note, category, amount, account, date range; shows total of results.
- No pantry/grocery integration. Groceries are normal expenses (Essentials / Treats quick buttons).
- Savings interest ignored. Month-end balance entry is the truth; difference shown as "adjustment".
- Security: app PIN lock on open; optional fingerprint/Face ID via WebAuthn (PIN is the fallback). Real security = login + RLS.
- Backups (free): manual Export (Excel + JSON) with "last backup X days ago" reminder, plus GitHub Actions job: daily keep-alive, weekly encrypted dump to a private repo. Verify pg_dump works on free plan when building.
- Supabase free projects pause after about a week of low usage (data kept) - keep-alive job handles it.
- Never commit secrets; .env in .gitignore; service key only in CI secrets.

## 4. Data model (from the Excel prototype)
- Household, membership(role), profile(language, pin settings local).
- Account: name, currency (SEK/LKR/configurable list), type (Spending/Savings), tracking (Detailed / Balance only), opening balance.
- Category: name (+translations for defaults), type (Income/Expense/Transfer), necessity (Fixed/Essential/Optional), visibility (Private/Shared), optional monthly budget.
- Transaction: date, type (Income/Expense/Transfer), category, account (default = first account), amount in the ACCOUNT's own currency, note, visibility override, deleted_at.
- Transfer: from account, to account, sent amount, received amount (both stored; this is real data, not a rate). Transfers are NEVER income or expense. Money sent to parents via Wise = Expense.
- Recurring template (bill or income): name, category, account, due day, active from, active until (optional), amount history (amount effective from month X; old months keep old amount).
- Recurring instance per month: expected amount, status pending/paid (bills) or pending/received (income), actual amount (editable, e.g. phone bill or salary reduced by sick leave), paid date.
- Balance update: account, date, actual balance (own currency). Balance-only accounts (Sri Lanka) use latest update.
- Month lock.
- Currency: data ALWAYS saved in account's own currency. Rate is typed only when using the "show everything in one currency" toggle (SEK/LKR); never stored with history.

## 5. Screens
Home (this month: received income vs expected, spent, pending bills total, safe-to-spend) | Add (3-tap entry, default account) | Bills (Pending vs Paid, due dates, tick, editable amount, total pending) | Income (expected vs received, tick, editable) | Accounts (balances, month-end update, transfers, SEK/LKR toggle) | Reports (month / 3m / 6m / year / custom range: income, expenses, by category, Fixed/Essential/Optional, trend, budgets, net worth) | Search | Settings (categories, recurring items, accounts, currencies, visibility, members/invites, language, PIN, backup/export, month lock).

## 6. Build phases (one phase = one chat/session, each ends with tests)
0. Foundation: repo, Supabase projects (real + demo), Vite/React/TS PWA shell, blue theme, i18n (si/en/sv), auth, CI skeleton.
1. Database: schema, migrations, RLS policies (household isolation, admin/member, Private/Shared), default categories seed, RLS tests.
2. Core entry: accounts, add/edit/delete/undo transactions, transfers, search, month lock.
3. Recurring bills & income: templates, amount history, pending/paid, tick, "mark everything before date as paid" for backfilling history.
4. Reports, Home, balances: date-range reports, budgets, net worth, month-end balance, reconciliation, SEK/LKR toggle with manually typed rate.
5. Members & sharing: invites, view-only members, Shared/Private enforcement and testing as a member.
6. Safety: PIN/biometric lock, Export Excel/JSON, backup reminder, GitHub Actions keep-alive + encrypted weekly backup.
7. Demo mode: separate Supabase project, "Try demo" (anonymous sign-in, own temporary household with seeded sample data, Reset button, scheduled cleanup, captcha/rate limit).
8. Portfolio polish: README, screenshots (from demo only), architecture notes, CV wording, optional Play Store (TWA) packaging.

## 7. Open items
- App name; email auth style (password vs magic link); currency list; whether accounts exist (Supabase, GitHub, Vercel/Cloudflare); demo method (per-visitor sandbox recommended); public GitHub repo yes/no.
