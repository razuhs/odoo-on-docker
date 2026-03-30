#!/bin/bash
set -e

# --------------------------------------
# Project root
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/configs"

echo "🧹 Cleaning project at: $PROJECT_ROOT"
echo ""

# --------------------------------------
# Preview directories
# --------------------------------------
echo "🔍 Directories to be removed:"

find "$PROJECT_ROOT" -maxdepth 1 -type d \( \
    -name "template*" -o \
    -name "test*" -o \
    -name "demo_stack" -o \
    -name "base_stack" -o \
    -name "caddy-sites" -o \
    -name "logs" -o \
    -name "custom-addons" \
\) -print

echo ""

# --------------------------------------
# Preview config files
# --------------------------------------
echo "🔍 Config files to be removed:"

if [[ -d "$CONFIG_DIR" ]]; then
    find "$CONFIG_DIR" -type f \( \
        -name ".template*" -o \
        -name ".test*" \
    \) -print
else
    echo "⚠️ Config directory not found: $CONFIG_DIR"
fi

echo ""
read -p "⚠️ Are you sure you want to delete ALL of the above? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Aborted"
    exit 0
fi

# --------------------------------------
# Delete directories
# --------------------------------------
echo ""
echo "🗑️ Removing directories..."

find "$PROJECT_ROOT" -maxdepth 1 -type d \( \
    -name "template*" -o \
    -name "test*" -o \
    -name "demo_stack" -o \
    -name "base_stack" -o \
    -name "caddy-sites" -o \
    -name "logs" -o \
    -name "custom-addons" \
\) -exec sudo rm -rf {} +

# --------------------------------------
# Delete config files
# --------------------------------------
echo "🗑️ Removing config files..."

if [[ -d "$CONFIG_DIR" ]]; then
    find "$CONFIG_DIR" -type f \( \
        -name ".template*" -o \
        -name ".test*" \
    \) -exec rm -f {} +
fi

# --------------------------------------
# Done
# --------------------------------------
echo ""
echo "🎉 FULL CLEANUP COMPLETE"