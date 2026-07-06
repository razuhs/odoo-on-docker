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

compose_cmd() {
    if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif sudo docker info >/dev/null 2>&1 && sudo docker compose version >/dev/null 2>&1; then
        sudo docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            docker-compose "$@"
        else
            sudo docker-compose "$@"
        fi
    else
        echo "❌ Docker Compose is not available. Install docker-compose-plugin or docker-compose."
        exit 1
    fi
}

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

    pick_pg_admin_user() {
        local candidate attempt
        local max_attempts=10
        local -a candidates=()
        local tried

        [[ -n "${DB_ADMIN_USER:-}" ]] && candidates+=("$DB_ADMIN_USER")
        candidates+=("postgres" "$DB_USER")

        for ((attempt=1; attempt<=max_attempts; attempt++)); do
            tried=""
            for candidate in "${candidates[@]}"; do
                [[ -z "$candidate" ]] && continue
                [[ " $tried " == *" $candidate "* ]] && continue
                tried="$tried $candidate"

                if docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$candidate" -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
                    PG_ADMIN_USER="$candidate"
                    return 0
                fi
            done

            if (( attempt < max_attempts )); then
                echo "⏳ Waiting for PostgreSQL admin connection... (attempt $attempt/$max_attempts)"
                sleep 2
            fi
        done

        return 1
    }

    PG_ADMIN_USER=""
    if ! pick_pg_admin_user; then
        echo "❌ Could not connect to PostgreSQL with any admin candidate user."
        echo "   Tried: DB_ADMIN_USER (if set), postgres, DB_USER=$DB_USER"
        echo "   You can set DB_ADMIN_USER in configs/.base_stack.conf if needed."
        exit 1
    fi

    echo "🔐 Using DB admin user: $PG_ADMIN_USER"

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
    db_exists=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='$db_name'")

    if [[ "$db_exists" == "1" ]]; then
        echo "⚠️ DB exists → dropping..."

                                                                docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$db_name'
          AND pid <> pg_backend_pid();
        "

                                                                docker_cmd exec -i "$POSTGRES_CONTAINER" dropdb -U "$PG_ADMIN_USER" "$db_name"

        echo "🗑️ DB dropped"
    fi

    # --------------------------------------
    # Create DB
    # --------------------------------------
    echo "🚀 Creating DB from template..."

    # Check if template DB exists
    template_exists=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='$template_db'")

    if [[ "$template_exists" != "1" ]]; then
        echo "❌ Template DB not found: $template_db"
        exit 1
    fi

    docker_cmd exec -i "$POSTGRES_CONTAINER" createdb \
        -U "$PG_ADMIN_USER" \
        -O "$DB_USER" \
        -T "$template_db" \
        "$db_name"

    echo "✅ DB created"
    # --------------------------------------
    # Ensure volume exists
    # --------------------------------------
    echo "🚀 Creating target volume via docker compose..."

    cd "$STACK_DIR"
    compose_cmd up -d

    # wait for volume creation
    sleep 2
    # --------------------------------------
    # Get UID/GID while container is running
    # --------------------------------------
    COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
    container_name=$(grep -m1 "container_name:" "$COMPOSE_FILE" | awk '{print $2}')

    ODOO_UID=$(docker_cmd exec "$container_name" id -u)
    ODOO_GID=$(docker_cmd exec "$container_name" id -g)

    echo "🔍 Detected UID:GID = ${ODOO_UID}:${ODOO_GID}"

    # now safe to stop
    compose_cmd stop

    # --------------------------------------
    # FILESTORE COPY
    # --------------------------------------

    TEMPLATE_VOLUME="${template_stack_name}_odoo_db_data"
    TARGET_VOLUME="${STACK_NAME}_odoo_db_data"

    # Validate volumes
    docker_cmd volume inspect "$TEMPLATE_VOLUME" >/dev/null 2>&1 || {
        echo "❌ Template volume not found"
        exit 1
    }

    docker_cmd volume inspect "$TARGET_VOLUME" >/dev/null 2>&1 || {
        echo "❌ Target volume not found"
        exit 1
    }

    echo "📦 From: $TEMPLATE_VOLUME"
    echo "📦 To:   $TARGET_VOLUME"

    # Copy filestore safely (auto-detect path + FIX PERMISSIONS)
        docker_cmd run --rm \
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

if [[ -n "$(compose_cmd ps -q)" ]]; then
    compose_cmd restart
else
    compose_cmd up -d
fi

echo "✅ Stack started"


# --------------------------------------
# Restart Caddy proxy
# --------------------------------------
if [[ "${SKIP_CADDY_RESTART:-false}" == "true" ]]; then
    echo "⏭️ Skipping Caddy restart (SKIP_CADDY_RESTART=true)"
else
    docker_cmd restart caddy-proxy
    echo "✅ Caddy restarted"
fi

echo "🌐 Waiting for instance to be accessible..."

START_TS=$(date +%s)
NEXT_CHECK_TS=$START_TS

# Extract port from compose file
PORT=$(grep -A5 "ports:" "$STACK_DIR/docker-compose.yml" | grep -oP '\d+:8069' | cut -d: -f1 | head -1)

URL="https://${DEMO_COMPANY_NAME}.${DOMAIN}/web/login"
HTTP_URL="http://${HOST_IP}:${PORT:-8069}"

is_odoo_ready() {
    local target_url="$1"
    local page

    page=$(curl -k -L -s --connect-timeout 2 --max-time 4 "$target_url" 2>/dev/null || true)
    [[ -n "$page" ]] || return 1

    # Consider ready only when login form fields are present.
    grep -qiE 'name=["'"'"']login["'"'"']' <<< "$page" && \
    grep -qiE 'name=["'"'"']password["'"'"']' <<< "$page"
}

while true; do
    NOW_TS=$(date +%s)
    WAITED=$((NOW_TS-START_TS))

    if (( NOW_TS >= NEXT_CHECK_TS )); then
        if is_odoo_ready "$URL" || is_odoo_ready "$HTTP_URL"; then
            break
        fi
        NEXT_CHECK_TS=$((NOW_TS+3))
    fi

    printf "\r⏳ Waiting... (%ss)" "$WAITED"
    sleep 1
done

echo

echo "✅ Instance is ready at: $URL"
echo "   (also accessible via $HTTP_URL)"
echo ""
echo ""
echo "🎉 Odoo Stack setup complete!"
echo ""
echo ""
