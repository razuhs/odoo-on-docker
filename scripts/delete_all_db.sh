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

POSTGRES_CONTAINER="postgres-container"
DRY_RUN=false

for arg in "$@"; do
	case "$arg" in
		-n|--dry-run)
			DRY_RUN=true
			;;
		-h|--help)
			echo "Usage: $0 [--dry-run|-n]"
			echo "  --dry-run, -n   Show what would be deleted without making changes"
			exit 0
			;;
		*)
			echo "❌ Unknown option: $arg"
			echo "Usage: $0 [--dry-run|-n]"
			exit 1
			;;
	esac
done

# --------------------------------------
# Load DB user
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$PROJECT_ROOT/configs/.base_stack.conf"

[[ -f "$BASE_CONFIG" ]] || { echo "❌ Base config not found: $BASE_CONFIG"; exit 1; }

# shellcheck disable=SC1090
source "$BASE_CONFIG"

[[ -n "$DB_USER" ]] || { echo "❌ DB_USER not found in base config"; exit 1; }

echo "⚠️ This will delete all non-system databases from PostgreSQL container: $POSTGRES_CONTAINER"
echo "✅ Protected databases: postgres, template0, template1"
if [[ "$DRY_RUN" == "true" ]]; then
	echo "🧪 DRY RUN MODE: no database will be deleted"
fi
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
	read -p "Type DELETE ALL to continue: " CONFIRM
	if [[ "$CONFIRM" != "DELETE ALL" ]]; then
		echo "❌ Aborted"
		exit 0
	fi
fi

DBS=$(docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -Atc "
SELECT datname
FROM pg_database
WHERE datistemplate = false
  AND datname NOT IN ('postgres', 'template0', 'template1')
ORDER BY datname;
")

mapfile -t DB_LIST <<< "$DBS"

if [[ -z "$DBS" ]]; then
	echo "ℹ️ No user databases found to delete."
	exit 0
fi

echo "🗄️ Databases to delete:"
for db in "${DB_LIST[@]}"; do
	[[ -n "$db" ]] && echo " - $db"
done

if [[ "$DRY_RUN" == "true" ]]; then
	echo ""
	echo "🔍 Planned actions:"
	for db in "${DB_LIST[@]}"; do
		[[ -z "$db" ]] && continue
		echo " - terminate active connections: $db"
		echo " - clear template flag if set: $db"
		echo " - drop database: $db"
	done
	echo ""
	echo "✅ Dry run complete. No changes were made."
	exit 0
fi

echo ""
for db in "${DB_LIST[@]}"; do
	[[ -z "$db" ]] && continue

	echo "🔌 Terminating active connections for: $db"
	docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
	SELECT pg_terminate_backend(pid)
	FROM pg_stat_activity
	WHERE datname = '$db'
	  AND pid <> pg_backend_pid();
	" >/dev/null 2>&1 || true

	echo "🔓 Clearing template flag (if set) for: $db"
	docker_cmd exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d postgres -c "
	ALTER DATABASE \"$db\" WITH is_template = false;
	" >/dev/null 2>&1 || true

	echo "🗑️ Dropping database: $db"
	docker_cmd exec -i "$POSTGRES_CONTAINER" dropdb -U "$DB_USER" "$db"
done

echo "✅ Completed: all non-system databases were deleted."
