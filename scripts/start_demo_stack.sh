#!/bin/bash

# ==========================================================
# SCRIPT: start_demo_stack.sh
# ==========================================================
#
# Purpose:
# --------
# Start a demo/test stack from a selected config file.
#
# This script can either:
# - create/recreate stack files via setup_demo_stack.sh, and
# - start/restart the stack containers,
# - optionally clone DB + filestore from a template stack when TEMPLATE=False.
#
# Usage:
# ------
# ./start_demo_stack.sh [config_file]
#
# Example:
# --------
# ./start_demo_stack.sh .demo19eewdd_stack.conf
#
# Input configs:
# --------------
# - configs/<config_file> (default: .demo_stack.conf)
# - configs/.base_stack.conf
#
# Key behavior:
# -------------
# 1. Loads demo and base config values.
# 2. Builds stack directory name from config filename.
# 3. Creates stack files if missing, or prompts for overwrite.
# 4. If TEMPLATE=False:
#    - creates DB by cloning from template DB,
#    - brings stack up once to create target volume,
#    - copies filestore from template volume to target volume,
#    - fixes ownership and permissions.
# 5. Starts or restarts stack containers.
# 6. Restarts caddy-proxy and waits until login URL is reachable.
#
# Template cloning logic:
# -----------------------
# - Selects template DB/volume names using version + edition + demo-data suffix.
# - Supports filestore path variants used by different Odoo versions.
# - Validates required docker volumes before copy.
#
# Output:
# -------
# - Running stack containers for selected demo config
# - Accessible login URL printed at the end
#
# Requirements:
# -------------
# - Docker and docker compose
# - Running postgres-container and caddy-proxy
# - Valid template DB/volume when TEMPLATE=False
# - curl for reachability check
#
# ==========================================================
set -e

# --------------------------------------
# Config
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DEFAULT_CONFIG=".demo_stack.conf"
CONFIG_NAME="${1:-$DEFAULT_CONFIG}"
CONFIG_FILE="$PROJECT_ROOT/configs/$CONFIG_NAME"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

# --------------------------------------
# Stack naming
# --------------------------------------
STACK_NAME="${CONFIG_NAME#.}"
STACK_NAME="${STACK_NAME%.conf}"
STACK_DIR="$PROJECT_ROOT/$STACK_NAME"

echo "🚀 Using config file: $CONFIG_FILE"
echo "🚀 Stack directory: $STACK_DIR"

# --------------------------------------
# Validate config file exists
# --------------------------------------
[[ -f "$CONFIG_FILE" ]] || { echo "❌ Config file not found"; exit 1; }
[[ -f "$BASE_CONFIG" ]] || { echo "❌ Base config not found"; exit 1; }

# --------------------------------------
# Load configs
# --------------------------------------
# shellcheck disable=SC1090
source "$CONFIG_FILE"
# shellcheck disable=SC1090
source "$BASE_CONFIG"

comp_name="${DEMO_COMPANY_NAME// /_}"
comp_name="${comp_name,,}"

odoo_version="${DEMO_ODOO_VERSION}"
db_name="${comp_name}-odoo${odoo_version}-db"

# --------------------------------------
# Setup or reuse stack directory
# --------------------------------------
if [[ ! -d "$STACK_DIR" ]]; then
    echo "🚀 Setting up stack..."
    bash "$PROJECT_ROOT/scripts/setup_demo_stack.sh" "$CONFIG_NAME" "$STACK_NAME"
else
    echo "⚠️ Stack directory already exists: $STACK_DIR"

    read -p "Overwrite existing files? (y/n): " choice
    case "$choice" in
        y|Y )
            sudo rm -rf "$STACK_DIR"
            bash "$PROJECT_ROOT/scripts/setup_demo_stack.sh" "$CONFIG_NAME" "$STACK_NAME"
            ;;
        n|N ) echo "✅ Keeping existing stack directory." ;;
        * ) echo "❌ Invalid input"; exit 1 ;;
    esac
fi

# --------------------------------------
# Validate docker-compose file
# --------------------------------------
[[ -f "$STACK_DIR/docker-compose.yml" ]] || { echo "❌ docker-compose.yml missing"; exit 1; }

# --------------------------------------
# TEMPLATE LOGIC
# --------------------------------------
TEMPLATE="${TEMPLATE:-False}"

if [[ "$TEMPLATE" == "False" ]]; then

    echo "🧠 Creating DB from template..."

    POSTGRES_CONTAINER="postgres-container"

    # --------------------------------------
    # Suffix mapping
    # --------------------------------------
    [[ "$DEMO_DATA" == "False" ]] && data_suffix="wdd" || data_suffix="wodd"
    [[ "$EDITION" == "EE" ]] && edition_part="ee" || edition_part="ce"

    # --------------------------------------
    # Names
    # --------------------------------------
    template_db="template${odoo_version}${edition_part}${data_suffix}-odoo${odoo_version}-db"
    template_stack_name="template${odoo_version}${edition_part}${data_suffix}_stack"

    echo "📚 Template DB: $template_db"
    echo "📦 New DB: $db_name"


    # --------------------------------------
    # Drop DB if exists
    # --------------------------------------
    db_exists=$(docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -tAc \
        "SELECT 1 FROM pg_database WHERE datname='$db_name'")

    if [[ "$db_exists" == "1" ]]; then
        echo "⚠️ DB exists → dropping..."

        docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$db_name'
          AND pid <> pg_backend_pid();
        "

        docker exec -i "$POSTGRES_CONTAINER" dropdb -U "$DB_USER" "$db_name"

        echo "🗑️ DB dropped"
    fi

    # --------------------------------------
    # Create DB
    # --------------------------------------
    echo "🚀 Creating DB from template..."

    docker exec -i "$POSTGRES_CONTAINER" createdb \
        -U "$DB_USER" \
        -T "$template_db" \
        "$db_name"

    echo "✅ DB created"
    # --------------------------------------
    # Ensure volume exists
    # --------------------------------------
    echo "🚀 Creating target volume via docker compose..."

    cd "$STACK_DIR"
    docker compose up -d

    # wait for volume creation
    sleep 2
    # --------------------------------------
    # Get UID/GID while container is running
    # --------------------------------------
    COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
    container_name=$(grep -m1 "container_name:" "$COMPOSE_FILE" | awk '{print $2}')

    ODOO_UID=$(docker exec "$container_name" id -u)
    ODOO_GID=$(docker exec "$container_name" id -g)

    echo "🔍 Detected UID:GID = ${ODOO_UID}:${ODOO_GID}"

    # now safe to stop
    docker compose stop

    # --------------------------------------
    # FILESTORE COPY
    # --------------------------------------

    TEMPLATE_VOLUME="${template_stack_name}_odoo_db_data"
    TARGET_VOLUME="${STACK_NAME}_odoo_db_data"

    # Validate volumes
    docker volume inspect "$TEMPLATE_VOLUME" >/dev/null 2>&1 || {
        echo "❌ Template volume not found"
        exit 1
    }

    docker volume inspect "$TARGET_VOLUME" >/dev/null 2>&1 || {
        echo "❌ Target volume not found"
        exit 1
    }

    echo "📦 From: $TEMPLATE_VOLUME"
    echo "📦 To:   $TARGET_VOLUME"

    # Copy filestore safely (auto-detect path + FIX PERMISSIONS)
    docker run --rm \
      -v "$TEMPLATE_VOLUME":/source \
      -v "$TARGET_VOLUME":/dest \
      alpine sh -c "
        if [ -d \"/source/filestore/${template_db}\" ]; then
            echo '📂 Detected filestore: /filestore (Odoo 18 style)'
            SRC=/source/filestore/${template_db}
            DEST=/dest/filestore/${db_name}
            BASE=/dest/filestore

        elif [ -d \"/source/.local/share/Odoo/filestore/${template_db}\" ]; then
            echo '📂 Detected filestore: .local/share/Odoo (Odoo 19 style)'
            SRC=/source/.local/share/Odoo/filestore/${template_db}
            DEST=/dest/.local/share/Odoo/filestore/${db_name}
            BASE=/dest/.local/share/Odoo/filestore

        else
            echo '❌ No valid filestore path found in template volume'
            exit 1
        fi

        mkdir -p \"\$BASE\" /dest/sessions

        echo \"📦 Copying: \$SRC → \$DEST\"

        rm -rf \"\$DEST\"
        cp -r \"\$SRC\" \"\$DEST\"

        echo '🔧 Fixing ownership + permissions...'

        # ownership
        chown -R ${ODOO_UID}:${ODOO_GID} /dest

        # directory permissions
        find /dest -type d -exec chmod 755 {} \;

        # file permissions
        find /dest -type f -exec chmod 644 {} \;

        # ensure writable dirs
        chmod -R 775 \"\$BASE\"
        chmod -R 775 /dest/sessions
      "

    echo "🔍 Using template volume: $TEMPLATE_VOLUME"
    echo "🔍 Using target volume:   $TARGET_VOLUME"
    echo "✅ Filestore copied and permissions fixed"
fi

# --------------------------------------
# Start / Restart containers
# --------------------------------------
echo "🚀 Starting stack: $STACK_NAME"
cd "$STACK_DIR"

if [[ -n "$(docker compose ps -q)" ]]; then
    docker compose restart
else
    docker compose up -d
fi

echo "✅ Stack started"

# --------------------------------------
# Restart Caddy proxy
# --------------------------------------
docker restart caddy-proxy
echo "✅ Caddy restarted"
URL="https://${DEMO_COMPANY_NAME}.${DOMAIN}/web/login"

echo "🌐 Waiting for instance to be accessible..."
echo "🔗 $URL"

MAX_WAIT=180
WAITED=0

until curl -k -L -s "$URL" >/dev/null 2>&1; do
    sleep 3
    WAITED=$((WAITED+3))

    if (( WAITED >= MAX_WAIT )); then
        echo "❌ Timeout: Instance not accessible"
        exit 1
    fi

    echo "⏳ Waiting... (${WAITED}s)"
done

echo "✅ Instance is accessible!"
echo "🌐 $URL"
