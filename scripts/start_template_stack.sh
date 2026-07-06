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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/configs"
BASE_CONFIG="$CONFIGS_DIR/.base_stack.conf"
POSTGRES_CONTAINER="postgres-container"

# Check if configs directory exists
if [ ! -d "$CONFIGS_DIR" ]; then
    echo "Error: configs directory not found at $CONFIGS_DIR"
    exit 1
fi

# Execute generate_template_configs.sh
"$SCRIPT_DIR/generate_template_configs.sh"

if [ ! -f "$BASE_CONFIG" ]; then
    echo "Error: base config not found at $BASE_CONFIG"
    exit 1
fi

# shellcheck disable=SC1090
source "$BASE_CONFIG"

if [ -z "$DB_USER" ]; then
    echo "Error: DB_USER is missing in $BASE_CONFIG"
    exit 1
fi

wait_for_postgres_capacity() {
    local min_free=20

    while true; do
        local stats max_conn used_conn free_conn
        stats=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -Atc "
            SELECT current_setting('max_connections')::int,
                   COUNT(*)::int
            FROM pg_stat_activity;
        " 2>/dev/null || true)

        if [[ -n "$stats" ]]; then
            max_conn="${stats%%|*}"
            used_conn="${stats##*|}"

            if [[ "$max_conn" =~ ^[0-9]+$ && "$used_conn" =~ ^[0-9]+$ ]]; then
                free_conn=$((max_conn-used_conn))
                if (( free_conn >= min_free )); then
                    printf "\r✅ PostgreSQL capacity OK (used:%s free:%s max:%s)\n" "$used_conn" "$free_conn" "$max_conn"
                    return 0
                fi

                printf "\r⏳ Waiting PostgreSQL capacity... (used:%s free:%s max:%s, need free>=%s)" "$used_conn" "$free_conn" "$max_conn" "$min_free"
            else
                printf "\r⏳ Waiting PostgreSQL stats..."
            fi
        else
            printf "\r⏳ Waiting PostgreSQL container/stats..."
        fi

        sleep 2
    done
}

wait_for_login_page() {
    local template_config="$1"
    local stack_name="$2"
    local template_file="$CONFIGS_DIR/$template_config"
    local stack_dir="$SCRIPT_DIR/../$stack_name"
    local url http_url port
    local start_ts now_ts waited next_check_ts

    if [ ! -f "$template_file" ]; then
        echo "Error: template config not found at $template_file"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$template_file"

    url="https://${DEMO_COMPANY_NAME}.${DOMAIN}/web/login"

    port=$(grep -A5 "ports:" "$stack_dir/docker-compose.yml" | grep -oP '\d+:8069' | cut -d: -f1 | head -1)
    http_url="http://${HOST_IP}:${port:-8069}"

    start_ts=$(date +%s)
    next_check_ts=$start_ts

    is_login_page_ready() {
        local target_url="$1"
        local page

        page=$(curl -k -L -s --connect-timeout 2 --max-time 4 "$target_url" 2>/dev/null || true)
        [[ -n "$page" ]] || return 1

        grep -qiE 'name=["'"'"']login["'"'"']' <<< "$page" && \
        grep -qiE 'name=["'"'"']password["'"'"']' <<< "$page"
    }

    echo "🌐 Confirming login page accessibility for: $stack_name"

    while true; do
        now_ts=$(date +%s)
        waited=$((now_ts-start_ts))

        if (( now_ts >= next_check_ts )); then
            if is_login_page_ready "$url" || is_login_page_ready "$http_url"; then
                echo
                echo "✅ Login page confirmed for: $stack_name"
                return 0
            fi
            next_check_ts=$((now_ts+3))
        fi

        printf "\r⏳ Waiting login page... (%ss)" "$waited"
        sleep 1
    done
}

# List all filenames in configs directory that start with .template
templates=($(ls -1 "$CONFIGS_DIR"/.template* 2>/dev/null | xargs -I {} basename {}))

# Check if any templates were found
if [ ${#templates[@]} -eq 0 ]; then
    echo "No template files found in configs directory"
    exit 1
fi

# Loop over each template
for template in "${templates[@]}"; do
    stack_name="${template#.}"
    stack_name="${stack_name%.conf}"

    echo "$template"
    wait_for_postgres_capacity
    "$SCRIPT_DIR/start_demo_stack.sh" "$template"
    wait_for_login_page "$template" "$stack_name"

    echo "📦 Finalizing template DB for: $stack_name"
    "$SCRIPT_DIR/make_template_db.sh" "$stack_name"
done
