#!/bin/bash
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

# ==========================================================
# 📘 DATABASE MANAGEMENT (ODOO DOCKER SETUP)
# ==========================================================
#
# 🔍 List all databases
# ---------------------
# ./list_databases.sh
#
# Example output:
#   database                          | is_template | conn_limit
# -----------------------------------+-------------+------------
#   bjit                              | NO          | -1
#   bjit-odoo19-db                    | NO          | -1
#   template19eewdd-odoo19-db         | YES         | 0
#   template19eewodd-odoo19-db        | YES         | 0
#
#
# 🧠 Column meaning:
# ------------------
# - database     → DB name
# - is_template  → YES = template DB, NO = normal DB
# - conn_limit   → 0 = locked (template), -1 = normal
#
#
# 🗑️ Delete a database
# ---------------------
# ./delete_db.sh <database_name>
#
# Example:
# ./delete_db.sh template19eewdd-odoo19-db
#
#
# ⚙️ What delete_db.sh does:
# -------------------------
# 1. Terminates active DB connections
# 2. Removes template flag (if exists)
# 3. Drops the database
#
#
# ⚠️ IMPORTANT:
# --------------
# This DOES NOT remove filestore (volume)
#
# You must manually remove volume:
# docker volume rm <stack_name>_odoo_db_data
#
# Example:
# docker volume rm template19eewdd_stack_odoo_db_data
#
#
# 🚨 WARNING:
# ------------
# Deleting a template DB means:
# - Cannot clone new instances from it
# - Must recreate template again
#
#
# 🔁 Recommended rebuild workflow:
# --------------------------------
# ./delete_db.sh <template_db>
# docker volume rm <template_volume>
# docker compose up -d
# ./make_template_db.sh <stack_name>
#
#
# ==========================================================

# --------------------------------------
# Input
# --------------------------------------
if [[ -z "$1" ]]; then
    echo "❌ Usage: $0 <database_name>"
    exit 1
fi

DB_NAME="$1"
POSTGRES_CONTAINER="postgres-container"

# --------------------------------------
# Load DB user
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

# shellcheck disable=SC1090
source "$BASE_CONFIG"

[[ -n "$DB_USER" ]] || { echo "❌ DB_USER not found"; exit 1; }

echo "🗄️ Target database: $DB_NAME"
echo ""

read -p "⚠️ This will PERMANENTLY DELETE the database. Continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Aborted"
    exit 0
fi

# --------------------------------------
# Check if DB exists
# --------------------------------------
db_exists=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -tAc \
"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")

if [[ "$db_exists" != "1" ]]; then
    echo "❌ Database does not exist: $DB_NAME"
    exit 1
fi

# --------------------------------------
# Terminate connections
# --------------------------------------
echo "🔌 Terminating active connections..."

docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME'
  AND pid <> pg_backend_pid();
" >/dev/null 2>&1 || true

# --------------------------------------
# Remove template flag (if any)
# --------------------------------------
echo "🔓 Removing template flag (if set)..."

docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
ALTER DATABASE \"$DB_NAME\" WITH is_template = false;
" >/dev/null 2>&1 || true

# --------------------------------------
# Drop database
# --------------------------------------
echo "🗑️ Dropping database..."

docker_cmd exec -i "$POSTGRES_CONTAINER" dropdb -U "$DB_USER" "$DB_NAME"

echo "✅ Database deleted: $DB_NAME"