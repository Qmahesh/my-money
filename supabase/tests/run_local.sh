#!/usr/bin/env bash
# Runs the database rules tests on a throw-away local PostgreSQL (needs postgres 14+ binaries).
# Usage: bash supabase/tests/run_local.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
DATA="$(mktemp -d)"
PORT="${PGPORT_TEST:-55432}"
SOCK="$DATA"

cleanup() { "$PGBIN/pg_ctl" -D "$DATA/db" stop -m immediate >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$PGBIN/initdb" -D "$DATA/db" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$DATA/db" -o "-p $PORT -k $SOCK -c listen_addresses=''" -w start >/dev/null

PSQL=("$PGBIN/psql" -h "$SOCK" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -o /dev/null)
"${PSQL[@]}" -c "create database mymoney" >/dev/null
PSQL+=( -d mymoney )

"${PSQL[@]}" -f "$HERE/supabase_stub.sql"
for f in "$HERE"/../migrations/*.sql; do
  echo "applying $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f "$HERE/rls_test.sql"
