#!/bin/bash
set -e

# --------------------------------------
# Config
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Default config file (with dot and .conf)
DEFAULT_CONFIG=".demo_stack.conf"

# Take argument if provided, otherwise fallback
CONFIG_NAME="${1:-$DEFAULT_CONFIG}"
CONFIG_FILE="$PROJECT_ROOT/configs/$CONFIG_NAME"

# Convert config file to stack directory name: remove leading dot and .conf
STACK_NAME="${CONFIG_NAME#.}"        # remove leading dot
STACK_NAME="${STACK_NAME%.conf}"     # remove .conf suffix
STACK_DIR="$PROJECT_ROOT/$STACK_NAME"

echo "🚀 Using config file: $CONFIG_FILE"
echo "🚀 Stack directory: $STACK_DIR"

# --------------------------------------
# Validate config file exists
# --------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

# --------------------------------------
# Setup or reuse stack directory
# --------------------------------------
if [[ ! -d "$STACK_DIR" ]]; then
    echo "⚠️ Stack directory not found: $STACK_DIR"
    echo "🚀 Setting up stack..."
    bash "$PROJECT_ROOT/scripts/setup_demo_stack.sh" "$CONFIG_NAME" "$STACK_NAME"
else
    echo "⚠️ Stack directory already exists: $STACK_DIR"

    read -p "Do you want to overwrite existing files. (y/n): " choice
    case "$choice" in
        y|Y )
            echo "🧹 Recreating stack directory..."
            sudo rm -rf "$STACK_DIR"
            bash "$PROJECT_ROOT/scripts/setup_demo_stack.sh" "$CONFIG_NAME" "$STACK_NAME"
            ;;
        n|N )
            echo "✅ Keeping existing stack directory."
            ;;
        * )
            echo "❌ Invalid input. Exiting."
            exit 1
            ;;
    esac
fi

# --------------------------------------
# Validate docker-compose file
# --------------------------------------
if [[ ! -f "$STACK_DIR/docker-compose.yml" ]]; then
    echo "❌ docker-compose.yml not found in $STACK_DIR"
    exit 1
fi

# --------------------------------------
# Start / Restart containers
# --------------------------------------
echo "🚀 Starting stack: $STACK_NAME"
cd "$STACK_DIR"

running_containers=$(docker compose ps -q)

if [[ -n "$running_containers" ]]; then
    echo "🔄 Containers already exist. Restarting..."
    docker compose restart
else
    echo "🚀 No existing containers. Starting fresh..."
    docker compose up -d
fi

echo ""
echo "✅ Stack started successfully"

# --------------------------------------
# Restart Caddy proxy
# --------------------------------------
echo "🔄 Restarting Caddy proxy..."
docker restart caddy-proxy
echo "✅ Caddy restarted successfully"