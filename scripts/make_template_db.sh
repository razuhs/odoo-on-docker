#!/bin/bash
# ==========================================================
# 📘 SCRIPT: make_template_db.sh
# ==========================================================
#
# 🚀 Purpose:
# ------------
# Converts an existing Odoo database into a PostgreSQL template
# database so it can be used for fast cloning of new instances.
#
#
# 🧾 Usage:
# ----------
# ./make_template_db.sh <stack_directory_name>
#
# Example:
# ./make_template_db.sh template19eewdd_stack
#
#
# ⚙️ What this script does:
# ------------------------
#
# 1. Extracts:
#    - Container name from docker-compose.yml
#    - Database name from Odoo startup command
#
# 2. Waits until the database is fully initialized:
#    - Ensures Odoo has finished installing modules
#    - Verifies table: ir_module_module exists
#
# 3. Checks if DB is already a template:
#    - If YES → validates and skips
#    - If NO  → proceeds to convert
#
# 4. Terminates active DB connections:
#    - Required before modifying DB properties
#
# 5. Marks database as template:
#    - Sets: datistemplate = true
#
# 6. Blocks new connections:
#    - Sets: connection limit = 0
#
# 7. Stops Odoo container:
#    - Template DB should not be used by a running instance
#
#
# 📦 Output:
# ----------
# ✔ Template Database:
#     <instance>-odoo<version>-db
#
# ✔ Associated Filestore Volume:
#     <stack_name>_odoo_db_data
#
# ✔ Container:
#     Stopped
#
#
# 🧠 Template Characteristics:
# ----------------------------
# - datistemplate = true
# - conn_limit = 0 (locked)
# - No active connections allowed
# - Used ONLY for cloning new instances
#
#
# 🔁 How it is used later:
# ------------------------
# When TEMPLATE=False in config:
#
#   - DB is cloned using:
#       createdb -T <template_db> <new_db>
#
#   - Filestore is copied:
#       template_db → new_db
#
#   - New instance becomes ready instantly
#
#
# ⚠️ Important Notes:
# -------------------
# - Always verify Odoo instance is running before executing
# - Do NOT run this on a broken or partially initialized DB
# - Template DB should NEVER be modified after creation
#
# - If template needs to be rebuilt:
#     → Delete DB
#     → Remove volume
#     → Recreate stack
#     → Run this script again
#
#
# 🔗 Related Scripts:
# -------------------
# - start_demo_stack.sh
#     → Create and start stack
#
# - generate_template_configs.sh
#     → Generate template config files
#
# - list_databases.sh
#     → Verify template status
#
# - delete_db.sh
#     → Remove DB if needed
#
# - remove_stack.sh
#     → Clean stack resources
#
#
# 💡 Tip:
# --------
# After execution, verify:
#
#   ./list_databases.sh
#
# Expected:
#   <template_db> → is_template = YES
#   conn_limit    → 0
#
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

# --------------------------------------
# Input
# --------------------------------------
if [[ -z "$1" ]]; then
    echo "❌ Usage: $0 <stack_directory_name>"
    exit 1
fi

STACK_NAME="$1"

# --------------------------------------
# Paths
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="$PROJECT_ROOT/$STACK_NAME"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

# --------------------------------------
# Validate
# --------------------------------------
[[ -d "$STACK_DIR" ]] || { echo "❌ Stack directory not found: $STACK_DIR"; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "❌ docker-compose.yml not found"; exit 1; }
[[ -f "$BASE_CONFIG" ]] || { echo "❌ Base config not found"; exit 1; }

# --------------------------------------
# Load DB user
# --------------------------------------
# shellcheck disable=SC1090
source "$BASE_CONFIG"

[[ -n "$DB_USER" ]] || { echo "❌ DB_USER not found"; exit 1; }

# --------------------------------------
# Extract container_name
# --------------------------------------
container_name=$(grep -m1 "container_name:" "$COMPOSE_FILE" | awk '{print $2}')
[[ -n "$container_name" ]] || { echo "❌ Failed to extract container_name"; exit 1; }

# --------------------------------------
# Extract DB name
# --------------------------------------
db_name=$(grep -oP 'odoo\s+-d\s+\K[^ ]+' "$COMPOSE_FILE" | head -n 1)
[[ -n "$db_name" ]] || { echo "❌ Failed to extract DB name"; exit 1; }

echo "📦 Container: $container_name"
echo "🗄️ Database: $db_name"

# --------------------------------------
# Wait for DB readiness
# --------------------------------------
POSTGRES_CONTAINER="postgres-container"

echo "⏳ Waiting for DB to be fully initialized..."

MAX_WAIT=300
WAITED=0

until docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$db_name" -c \
"SELECT 1 FROM ir_module_module LIMIT 1;" >/dev/null 2>&1; do

    sleep 5
    WAITED=$((WAITED+5))

    if (( WAITED >= MAX_WAIT )); then
        echo "❌ Timeout waiting for DB readiness"
        exit 1
    fi
done

echo "✅ DB is ready"

# --------------------------------------
# Check if already template
# --------------------------------------
template_exists=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='$db_name' AND datistemplate=true")

if [[ "$template_exists" == "1" ]]; then
    echo "⚠️ Template DB already exists: $db_name"

    # Optional validation
    db_valid=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$db_name" -tAc \
        "SELECT count(*) FROM ir_module_module")

    if [[ "$db_valid" -gt 0 ]]; then
        echo "✅ Template DB looks valid"
    else
        echo "❌ Template DB exists but looks invalid"
        exit 1
    fi

    echo "⏭ Skipping template creation (immutable template)"
    exit 0
fi

# --------------------------------------
# Terminate connections
# --------------------------------------
echo "🔌 Terminating DB connections..."

docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$db_name'
  AND pid <> pg_backend_pid();
"

# --------------------------------------
# Mark as template
# --------------------------------------
echo "📦 Marking DB as template..."

docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
ALTER DATABASE \"$db_name\" WITH is_template = true;
"

# --------------------------------------
# Block connections
# --------------------------------------
echo "🔒 Blocking connections..."

docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
ALTER DATABASE \"$db_name\" CONNECTION LIMIT 0;
"

# --------------------------------------
# Stop container safely
# --------------------------------------
if docker_cmd ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    echo "🛑 Stopping container..."
    docker_cmd stop "$container_name"
else
    echo "ℹ️ Container already stopped"
fi

echo ""
echo "🎉 TEMPLATE READY: $db_name"