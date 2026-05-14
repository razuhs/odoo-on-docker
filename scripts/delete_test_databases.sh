#!/bin/bash

# ==========================================================
# SCRIPT: delete_test_databases.sh
# ==========================================================
#
# Purpose:
# --------
# Find all databases starting with "test" and delete them
# using the delete_db.sh script.
#
# Usage:
# ------
# ./delete_test_databases.sh
#
# Behavior:
# ---------
# 1. Runs list_databases.sh to fetch all databases.
# 2. Filters databases starting with "test".
# 3. For each test database, runs delete_db.sh with confirmation.
# 4. Reports summary of deleted and skipped databases.
#
# Requirements:
# -------------
# - list_databases.sh available in same directory
# - delete_db.sh available in same directory
# - Docker with running postgres-container
# - Valid DB_USER in configs/.base_stack.conf
#
# Notes:
# ------
# - Each deletion requires explicit "yes" confirmation.
# - Does NOT delete filestore volumes (use docker volume rm manually).
#
# ==========================================================
set -e

echo "🔍 Fetching all databases..."
echo ""

# Get database list from list_databases.sh and filter for 'test' prefix.
# list_databases.sh prints table output, so trim column 1 and match /^test/.
mapfile -t TEST_DBS < <(
    ./list_databases.sh 2>/dev/null | awk -F'|' '
        function trim(s) {
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }
        NF >= 3 {
            db = trim($1)
            if (db ~ /^test/) {
                print db
            }
        }
    '
)

if [[ ${#TEST_DBS[@]} -eq 0 ]]; then
    echo "✅ No test databases found."
    exit 0
fi

echo "📋 Test databases found:"
for db in "${TEST_DBS[@]}"; do
    echo "   - $db"
done
echo ""

# Loop through and delete each test database
DELETED_COUNT=0
SKIPPED_COUNT=0

for db_name in "${TEST_DBS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ./delete_db.sh "$db_name"; then
        DELETED_COUNT=$((DELETED_COUNT + 1))
    else
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
    
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Summary:"
echo "   ✅ Deleted: $DELETED_COUNT"
echo "   ⏭️  Skipped: $SKIPPED_COUNT"
echo ""
echo "🎉 Test database cleanup complete."
