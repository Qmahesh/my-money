# My Money

A simple, private money tracker for a family: income, expenses, bills, transfers and account balances.
Mobile-first web app (PWA) with English, Sinhala (සිංහල) and Swedish (Svenska) interface.

**Status:** Steps 0-1 of 8 done (app shell, 3 languages, login; database + security rules with automated tests).
See [docs/PROJECT_SPEC.md](docs/PROJECT_SPEC.md) for all decisions and the build plan.

## Database
See [supabase/README.md](supabase/README.md).

## Tech
React + TypeScript (Vite) - PWA - Supabase (Postgres, Auth, Row Level Security) - Vercel - GitHub Actions.
Everything runs on free tiers.

## Run locally (optional)
```bash
npm install
cp .env.example .env   # then fill in the two values
npm run dev
```
Other commands: `npm run typecheck`, `npm test`, `npm run build`.

## Configuration
The app needs two environment variables (see `.env.example`):

| Name | Where to find it |
|---|---|
| `VITE_SUPABASE_URL` | Supabase project > Project Settings > API (Project URL) |
| `VITE_SUPABASE_ANON_KEY` | same page: the public "anon" or "publishable" key |

The anon/publishable key is designed to be public (the database rules protect the data).
**Never** use or commit the `service_role` / secret key in this project.
