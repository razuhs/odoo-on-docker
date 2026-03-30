#!/bin/bash
# ==========================================================
# 📘 SCRIPT: list_databases.sh
# ==========================================================
#
# 🔍 Purpose:
# ------------
# Lists all PostgreSQL databases and identifies:
# - Template databases
# - Normal databases
# - Connection limits
#
#
# 🚀 Usage:
# ----------
# ./list_databases.sh
#
#
# 📊 Example Output:
# ------------------
#   database                          | is_template | conn_limit
# -----------------------------------+-------------+------------
#   bjit                              | NO          | -1
#   bjit-odoo19-db                    | NO          | -1
#   postgres                          | NO          | -1
#   template0                         | YES         | -1
#   template1                         | YES         | -1
#   template19eewdd-odoo19-db         | YES         | 0
#   template19eewodd-odoo19-db        | YES         | 0
#
#
# 🧠 Column Explanation:
# ----------------------
# - database
#     → Name of the database
#
# - is_template
#     → YES  = Template database (used for cloning)
#     → NO   = Normal database (active usage)
#
# - conn_limit
#     → 0   = No connections allowed (template DB, locked)
#     → -1  = Unlimited connections (normal DB)
#
#
# 🟢 Template Databases:
# ----------------------
# - Used as base for creating new Odoo instances
# - Marked with:
#     is_template = YES
#     conn_limit = 0
# - Should NOT be modified or used directly
#
#
# ⚪ Normal Databases:
# -------------------
# - Active Odoo databases
# - Accept user connections
# - Used by running containers
#
#
# ⚠️ Notes:
# ----------
# - This script only LISTS databases
# - It does NOT modify or delete anything
# - Safe to run anytime
#
#
# 🔗 Related Scripts:
# -------------------
# - delete_db.sh
#     → Deletes a database (template or normal)
# 💡 Tip:
# --------
# If a database has:
#   is_template = YES
#   conn_limit = 0
#
# Then it is a properly configured Odoo template
#
#
# ==========================================================
set -e

POSTGRES_CONTAINER="postgres-container"

# --------------------------------------
# Load DB user
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

# shellcheck disable=SC1090
source "$BASE_CONFIG"

[[ -n "$DB_USER" ]] || { echo "❌ DB_USER not found"; exit 1; }

echo "📊 Listing PostgreSQL databases..."
echo ""

# --------------------------------------
# Query databases
# --------------------------------------
docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
SELECT
    datname AS database,
    CASE
        WHEN datistemplate THEN 'YES'
        ELSE 'NO'
    END AS is_template,
    datconnlimit AS conn_limit
FROM pg_database
WHERE datistemplate = false OR datname LIKE 'template%'
ORDER BY datname;
"