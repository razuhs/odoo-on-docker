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

usage() {
    echo "Usage: $0 [--watch|-w] [--interval|-i <seconds>] [--count|-c <runs>] [--top|-t <rows>] [--all|-a]"
    echo ""
    echo "Options:"
    echo "  --watch, -w           Continuously print connection usage"
    echo "  --interval, -i N      Seconds between checks (default: 5)"
    echo "  --count, -c N         Number of checks to run (default: 1; in watch mode: unlimited)"
    echo "  --top, -t N           Show top N rows in DB/user tables (default: 10)"
    echo "  --all, -a             Show all DB/user rows (no LIMIT)"
    echo "  --help, -h            Show this help"
}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"
POSTGRES_CONTAINER="postgres-container"

WATCH=false
INTERVAL=5
COUNT=1
TOP_N=10
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--watch)
            WATCH=true
            shift
            ;;
        -i|--interval)
            [[ $# -ge 2 ]] || { echo "❌ Missing value for $1"; usage; exit 1; }
            INTERVAL="$2"
            shift 2
            ;;
        -c|--count)
            [[ $# -ge 2 ]] || { echo "❌ Missing value for $1"; usage; exit 1; }
            COUNT="$2"
            shift 2
            ;;
        -t|--top)
            [[ $# -ge 2 ]] || { echo "❌ Missing value for $1"; usage; exit 1; }
            TOP_N="$2"
            shift 2
            ;;
        -a|--all)
            SHOW_ALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

[[ "$INTERVAL" =~ ^[0-9]+$ ]] || { echo "❌ interval must be a positive integer"; exit 1; }
[[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "❌ count must be a non-negative integer"; exit 1; }
[[ "$TOP_N" =~ ^[0-9]+$ ]] || { echo "❌ top must be a non-negative integer"; exit 1; }
if [[ "$SHOW_ALL" == "false" && "$TOP_N" -eq 0 ]]; then
    echo "❌ top must be greater than 0, or use --all"
    exit 1
fi
[[ -f "$BASE_CONFIG" ]] || { echo "❌ Base config not found: $BASE_CONFIG"; exit 1; }
# shellcheck disable=SC1090
source "$BASE_CONFIG"
[[ -n "${DB_USER:-}" ]] || { echo "❌ DB_USER not found in base config"; exit 1; }

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

print_report() {
    local summary_line
    local ts

    summary_line=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -tA -F $'\t' -c "
WITH s AS (
    SELECT
        current_setting('max_connections')::int AS max_conn,
        current_setting('superuser_reserved_connections')::int AS reserved_conn,
        count(*)::int AS used_conn,
        count(*) FILTER (WHERE state = 'active')::int AS active_conn,
        count(*) FILTER (WHERE state = 'idle')::int AS idle_conn,
        count(*) FILTER (WHERE wait_event_type IS NOT NULL)::int AS waiting_conn
    FROM pg_stat_activity
)
SELECT
    max_conn,
    reserved_conn,
    used_conn,
    active_conn,
    idle_conn,
    waiting_conn,
    GREATEST(max_conn - reserved_conn - used_conn, 0) AS free_non_super,
    round((used_conn::numeric * 100) / NULLIF(max_conn, 0), 2) AS used_pct
FROM s;
")

    IFS=$'\t' read -r max_conn reserved_conn used_conn active_conn idle_conn waiting_conn free_non_super used_pct <<< "$summary_line"

    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo ""
    echo "📊 PostgreSQL Connection Health [$ts]"
    echo "   max_connections:              $max_conn"
    echo "   superuser_reserved:           $reserved_conn"
    echo "   currently_used:               $used_conn (${used_pct}%)"
    echo "   active:                       $active_conn"
    echo "   idle:                         $idle_conn"
    echo "   waiting_event:                $waiting_conn"
    echo "   free_non_superuser_slots:     $free_non_super"
    echo ""

    if [[ "$SHOW_ALL" == "true" ]]; then
        echo "📚 All databases by open connections"
        docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -c "
SELECT
    COALESCE(datname, '(none)') AS database,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY datname
ORDER BY connections DESC, database;
"

        echo "👤 All users by open connections"
        docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -c "
SELECT
    COALESCE(usename, '(none)') AS db_user,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY usename
ORDER BY connections DESC, db_user;
"
    else
        echo "🔝 Top ${TOP_N} databases by open connections"
        docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -c "
SELECT
    COALESCE(datname, '(none)') AS database,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY datname
ORDER BY connections DESC, database
LIMIT ${TOP_N};
"

        echo "👤 Top ${TOP_N} users by open connections"
        docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$PG_ADMIN_USER" -d postgres -c "
SELECT
    COALESCE(usename, '(none)') AS db_user,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY usename
ORDER BY connections DESC, db_user
LIMIT ${TOP_N};
"
    fi
}

PG_ADMIN_USER=""
if ! pick_pg_admin_user; then
    echo "❌ Could not connect to PostgreSQL with any admin candidate user."
    echo "   Tried: DB_ADMIN_USER (if set), postgres, DB_USER=$DB_USER"
    echo "   You can set DB_ADMIN_USER in configs/.base_stack.conf if needed."
    exit 1
fi

echo "🔐 Using DB admin user: $PG_ADMIN_USER"

if [[ "$WATCH" == "true" && "$COUNT" -eq 1 ]]; then
    COUNT=0
fi

run_index=0
while true; do
    print_report

    ((run_index += 1))

    if [[ "$WATCH" != "true" ]]; then
        break
    fi

    if [[ "$COUNT" -gt 0 && "$run_index" -ge "$COUNT" ]]; then
        break
    fi

    sleep "$INTERVAL"
done
