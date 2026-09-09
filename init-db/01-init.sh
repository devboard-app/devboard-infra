#!/bin/bash
#
# Creates the five service roles and databases.
#
# Postgres runs everything in /docker-entrypoint-initdb.d exactly once, when the
# data directory is empty. A .sh file (unlike the .sql this replaces) has the
# container's environment available, so the real passwords come from
# devboard-infra/.env instead of being hardcoded placeholders.
#
# This is what makes the stack portable: `docker compose -f stack.yml up` now
# provisions the databases on any OS, with no setup.bat involved.
#
# Note it does NOT run against an existing volume. setup.bat keeps its own
# create-user logic as the path for already-initialised installs.

set -euo pipefail

create_role_and_db() {
    local role="$1" db="$2" password="$3"

    if [ -z "$password" ]; then
        echo "  SKIP  $role — no password in the environment (check devboard-infra/.env)" >&2
        return 0
    fi

    # format() with %I/%L quotes the identifier and literal properly, so a
    # password containing quotes can't break out. \gexec runs the generated
    # statement, and only when the guard row is produced.
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
         -v role="$role" -v pw="$password" -q <<-'EOSQL'
        SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pw')
        WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role')
        \gexec
EOSQL

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
         -v role="$role" -v db="$db" -q <<-'EOSQL'
        SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db')
        \gexec
EOSQL

    echo "  ok    $role / $db"
}

echo "=== DevBoard: provisioning service roles and databases ==="

create_role_and_db auth_user         auth_db         "${AUTH_DB_PASSWORD:-}"
create_role_and_db core_user         core_db         "${CORE_DB_PASSWORD:-}"
create_role_and_db work_user         work_db         "${WORK_DB_PASSWORD:-}"
create_role_and_db integrations_user integrations_db "${INTEGRATIONS_DB_PASSWORD:-}"
create_role_and_db attachments_user  attachments_db  "${ATTACHMENTS_DB_PASSWORD:-}"

echo "=== done ==="
