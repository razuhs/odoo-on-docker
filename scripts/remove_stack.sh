#!/bin/bash
set -e

# --------------------------------------
# Input
# --------------------------------------
if [[ -z "$1" ]]; then
    echo "❌ Usage: $0 <stack_directory_name> [--with-db]"
    exit 1
fi

STACK_NAME="$1"
DELETE_DB_FLAG="$2"

# --------------------------------------
# Paths
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="$PROJECT_ROOT/$STACK_NAME"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

ODOO_LOG_DIR="$PROJECT_ROOT/logs/odoo-logs"
CADDY_LOG_DIR="$PROJECT_ROOT/logs/caddy-logs"
CADDY_SITES_DIR="$PROJECT_ROOT/caddy-sites"

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
# Extract DB + container name
# --------------------------------------
db_name=$(grep -oP 'odoo\s+-d\s+\K[^ ]+' "$COMPOSE_FILE" | head -n 1)
container_name=$(grep -m1 "container_name:" "$COMPOSE_FILE" | awk '{print $2}')

echo "📦 Stack: $STACK_NAME"
echo "📦 Container: $container_name"
echo "🗄️ Database: $db_name"

cd "$STACK_DIR"

echo ""
echo "⚠️ This will COMPLETELY REMOVE:"
echo "   - Containers"
echo "   - Volumes (filestore will be LOST)"
echo "   - Stack directory"
echo "   - Logs (Odoo + Caddy)"
echo "   - Caddy site config"

if [[ "$DELETE_DB_FLAG" == "--with-db" ]]; then
    echo "   - Database (INCLUDING TEMPLATE)"
fi

echo ""
read -p "Are you sure? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Aborted"
    exit 0
fi

# --------------------------------------
# Stop and remove containers
# --------------------------------------
echo "🛑 Removing containers..."
docker compose down --remove-orphans

# --------------------------------------
# Remove volumes
# --------------------------------------
echo "🧹 Removing volumes..."
docker compose down -v --remove-orphans

# --------------------------------------
# Remove leftover volumes
# --------------------------------------
echo "🔍 Cleaning leftover volumes..."

VOLUMES=$(docker volume ls --format '{{.Name}}' | grep "^${STACK_NAME}_odoo_db_data" || true)

if [[ -n "$VOLUMES" ]]; then
    echo "$VOLUMES" | xargs -r docker volume rm
fi

# --------------------------------------
# Delete database (INCLUDING template)
# --------------------------------------
if [[ "$DELETE_DB_FLAG" == "--with-db" ]]; then

    echo "🗑️ Removing database: $db_name"

    POSTGRES_CONTAINER="postgres-container"

    docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '$db_name'
      AND pid <> pg_backend_pid();
    " >/dev/null 2>&1 || true

    docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
    ALTER DATABASE \"$db_name\" WITH is_template = false;
    " >/dev/null 2>&1 || true

    docker exec -i "$POSTGRES_CONTAINER" dropdb -U "$DB_USER" "$db_name" >/dev/null 2>&1 || true

    echo "✅ Database removed"
fi

# --------------------------------------
# Remove logs
# --------------------------------------
echo "🧹 Removing logs..."

sudo rm -f "$ODOO_LOG_DIR/${container_name}.log" 2>/dev/null || true
sudo rm -f "$CADDY_LOG_DIR/${container_name}_access.log" 2>/dev/null || true

echo "✅ Logs removed"

# --------------------------------------
# Remove caddy site config
# --------------------------------------
echo "🧹 Removing Caddy site..."

sudo rm -f "$CADDY_SITES_DIR/${container_name}.caddy" 2>/dev/null || true

echo "✅ Caddy site removed"

# --------------------------------------
# Remove stack directory
# --------------------------------------
echo "🧹 Removing stack directory..."

sudo rm -rf "$STACK_DIR"

echo "✅ Stack directory removed"

# --------------------------------------
# Done
# --------------------------------------
echo ""
echo "🎉 FULL CLEANUP COMPLETE for '$STACK_NAME'"
