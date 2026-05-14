#!/bin/bash

# ==========================================================
# SCRIPT: remove_stack.sh
# ==========================================================
#
# Purpose:
# --------
# Fully remove a stack environment, including containers,
# volumes, stack files, and related logs/site config.
#
# Usage:
# ------
# ./remove_stack.sh <stack_directory_name> [--with-db]
#
# Examples:
# ---------
# ./remove_stack.sh demo_stack
# ./remove_stack.sh demo_stack --with-db
#
# Behavior:
# ---------
# - Validates stack directory and required config files.
# - Detects database name and container name from docker-compose.yml.
# - Runs docker compose down and volume cleanup.
# - Removes stack log files and Caddy site config.
# - Permanently deletes filestore data (all volumes).
# - Deletes stack directory from disk.
# - If --with-db is passed, also drops the stack database.
#
# Permanent deletion includes:
# ---------------------------
# - ALL Docker volumes associated with the stack (filestore data)
# - Stack configuration and Dockerfile
# - All logs (Odoo + Caddy)
# - Caddy site routing config
#
# Database Deletion Mode:
# -----------------------
# When --with-db is provided, the script will:
# 1. Terminate active DB connections
# 2. Disable template mode on the DB (if enabled)
# 3. Drop the database
#
# Safety:
# -------
# - Prompts for explicit confirmation before destructive actions.
# - Without "yes" confirmation, script exits without deleting resources.
#
# Requirements:
# -------------
# - Docker and docker compose available
# - Access to postgres-container
# - Valid DB_USER in configs/.base_stack.conf
# - sudo permission for file/log cleanup
#
# ==========================================================
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
DELETE_FILESTORE="no"

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
echo "   - Stack directory"
echo "   - Logs (Odoo + Caddy)"
echo "   - Caddy site config"

if [[ "$DELETE_DB_FLAG" == "--with-db" ]]; then
    echo "   - Database (INCLUDING TEMPLATE)"
    echo "   - Filestore volumes (ASKED SEPARATELY)"
else
    echo "   - Filestore volumes (NOT deleted)"
fi

echo ""
read -p "Are you sure? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Aborted"
    exit 0
fi

if [[ "$DELETE_DB_FLAG" == "--with-db" ]]; then
    read -p "Also delete filestore volumes? (yes/no): " FILESTORE_CONFIRM

    case "$FILESTORE_CONFIRM" in
        yes|y|Y|YES)
            DELETE_FILESTORE="yes"
            ;;
        no|n|N|NO)
            DELETE_FILESTORE="no"
            ;;
        *)
            echo "❌ Invalid input. Please use yes or no."
            exit 1
            ;;
    esac
fi

# --------------------------------------
# Stop and remove containers
# --------------------------------------
echo "🛑 Removing containers..."
docker compose down --remove-orphans

# --------------------------------------
# Delete database (INCLUDING template)
# --------------------------------------
if [[ "$DELETE_DB_FLAG" == "--with-db" ]]; then

    # --------------------------------------
    # Optional filestore deletion (only when --with-db is used)
    # --------------------------------------
    if [[ "$DELETE_FILESTORE" == "yes" ]]; then
        echo "🧹 Removing selected stack filestore volume only..."

        # Compose project-name defaults to directory name, so this resolves to
        # the exact filestore volume for the selected stack.
        FILESTORE_VOLUME="${STACK_NAME}_odoo_db_data"

        if docker volume inspect "$FILESTORE_VOLUME" >/dev/null 2>&1; then
            echo "📦 Removing filestore volume: $FILESTORE_VOLUME"
            docker volume rm "$FILESTORE_VOLUME"
            echo "✅ Filestore volume removed"
        else
            echo "ℹ️ Filestore volume not found: $FILESTORE_VOLUME"
        fi
    else
        echo "⏭️ Keeping filestore volumes (user chose not to delete)."
    fi

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
else
    echo "⏭️ --with-db not provided. Skipping database and filestore deletion."
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
