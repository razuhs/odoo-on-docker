#!/bin/bash

# ==========================================================
# SCRIPT: update_database_expiration.sh
# ==========================================================
#
# Purpose:
# --------
# Update the database expiration date in all valid Odoo databases
# by setting ir_config_parameter key "database.expiration_date".
#
# Usage:
# ------
# ./update_database_expiration.sh
#
# Behavior:
# ---------
# 1. Connects to running postgres-container.
# 2. Fetches all non-template, non-test, non-postgres databases.
# 3. For each database:
#    - Checks if ir_config_parameter table exists.
#    - Inserts or updates the database.expiration_date key.
#    - Sets value to EXPIRATION_DATE (2027-12-31).
#
# Database filtering:
# -------------------
# - Excludes databases starting with "template"
# - Excludes databases starting with "test"
# - Excludes built-in "postgres" database
# - Includes only databases that allow connections
#
# Input config:
# -------------
# - configs/.base_stack.conf
#   Required: DB_USER
#
# Expiration date:
# ----------------
# - Hardcoded: 2027-12-31
# - Can be modified in the script variable EXPIRATION_DATE
#
# Requirements:
# -------------
# - Docker with running postgres-container
# - psql tool inside postgres-container
# - Valid DB_USER in base config
#
# ==========================================================
set -e

docker_cmd() {
    if docker info >/dev/null 2>&1; then
        docker "$@"
    elif sudo docker info >/dev/null 2>&1; then
        sudo docker "$@"
    else
        echo "❌ Docker is not accessible. Ensure daemon is running and user has permissions."
        exit 1
    fi
}

POSTGRES_CONTAINER="postgres-container"
EXPIRATION_DATE="2027-12-31"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

# shellcheck disable=SC1090
source "$BASE_CONFIG"

[[ -n "$DB_USER" ]] || { echo "❌ DB_USER not found"; exit 1; }

echo "🔎 Fetching databases to update..."

mapfile -t DATABASES < <(
    docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -tA -c "
SELECT datname
FROM pg_database
WHERE datallowconn
  AND datname !~ '^(template|test|postgres)'
ORDER BY datname;
"
)

if [[ ${#DATABASES[@]} -eq 0 ]]; then
    echo "No matching databases found."
    exit 0
fi

echo "Databases: ${DATABASES[*]}"

for database_name in "${DATABASES[@]}"; do
    echo "Updating ${database_name}..."

    table_exists=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$database_name" -tA -c "
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'ir_config_parameter';
")

    if [[ "$table_exists" != "1" ]]; then
        echo "Skipping ${database_name}: ir_config_parameter not found."
        continue
    fi

    docker_cmd exec -i "$POSTGRES_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$database_name" <<SQL
INSERT INTO ir_config_parameter (key, value, create_uid, create_date, write_uid, write_date)
VALUES ('database.expiration_date', '${EXPIRATION_DATE}', 1, NOW(), 1, NOW())
ON CONFLICT (key)
DO UPDATE SET
    value = EXCLUDED.value,
    write_uid = EXCLUDED.write_uid,
    write_date = EXCLUDED.write_date;
SQL

    echo "✅ Updated ${database_name}"
done

echo "Finished updating database expiration dates to ${EXPIRATION_DATE}."