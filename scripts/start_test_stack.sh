#!/bin/bash

set -euo pipefail

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

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"
POSTGRES_CONTAINER="postgres-container"

[[ -f "$BASE_CONFIG" ]] || { echo "❌ Base config not found: $BASE_CONFIG"; exit 1; }
# shellcheck disable=SC1090
source "$BASE_CONFIG"
[[ -n "${DB_USER:-}" ]] || { echo "❌ DB_USER not found in base config"; exit 1; }

wait_for_postgres_slot() {
    local max_attempts=30
    local attempt

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        if docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
            return 0
        fi
        echo "⏳ PostgreSQL is saturated or unavailable (attempt $attempt/$max_attempts)."
        sleep 2
    done

    return 1
}

# Call and execute generate_test_configs.sh
./generate_test_configs.sh

# Get list of all files in configs that start with ".test"
test_files=$(cd ../configs && ls .test* 2>/dev/null && cd - > /dev/null)

# Loop over the test files and call ./start_demo_stack with each file name
for file in $test_files; do
    if ! wait_for_postgres_slot; then
        echo "❌ PostgreSQL stayed saturated. Stopping remaining stack startups."
        echo "   Tip: reduce per-instance DB usage via DB_MAXCONN in configs/.base_stack.conf and restart stacks."
        exit 1
    fi

    echo ""
    echo ""
    echo "Starting stack for config: $file"
    SKIP_CADDY_RESTART=true ./start_demo_stack.sh "$file"
    echo ""
    echo ""
done

echo "🔁 Restarting Caddy once after batch startup..."
docker_cmd restart caddy-proxy
echo "✅ Caddy restarted"