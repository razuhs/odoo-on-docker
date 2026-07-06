#!/bin/bash

# ==========================================================
# SCRIPT: start_base_stack.sh
# ==========================================================
#
# Purpose:
# --------
# End-to-end bootstrap for the base Odoo stack. This script prepares
# Docker, builds base images, ensures base stack files exist, and starts
# or restarts the base docker compose services.
#
# Usage:
# ------
# ./start_base_stack.sh
#
# Input configuration:
# --------------------
# - configs/.base_stack.conf
#   Required keys include COMPANY_NAME, ODOO_VERSION, DOMAIN, and other
#   values consumed by dependent scripts.
#
# Execution steps:
# ----------------
# 1. Prepare Docker environment
#    -> runs scripts/prepare_docker.sh
#
# 2. Build Odoo base images
#    -> runs scripts/build_odoo_base_images.sh
#
# 3. Ensure base stack files
#    -> if base_stack exists, prompts for fresh setup
#    -> runs scripts/setup_base_stack.sh when creating fresh files
#
# 4. Verify required files in base_stack
#    -> waits up to 30 seconds per file for generated artifacts
#
# 5. Start or restart docker compose stack
#    -> restart if containers already exist
#    -> up -d if no existing containers are found
#
# Output:
# -------
# - Running base stack containers
# - Final URL print: https://<DOMAIN>/odoo
#
# Safety and prompts:
# -------------------
# - Existing base_stack directory is not removed unless user confirms.
# - Script exits on missing config/required files/timeouts.
#
# Requirements:
# -------------
# - Docker and docker compose available
# - sudo permission for file operations in dependent scripts
# - Valid configs/.base_stack.conf
#
# ==========================================================
set -e

COMPOSE_MODE=""

resolve_compose_mode() {
    if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        COMPOSE_MODE="docker-compose-plugin"
        return
    fi

    if sudo -n docker info >/dev/null 2>&1 && sudo -n docker compose version >/dev/null 2>&1; then
        COMPOSE_MODE="sudo-docker-compose-plugin"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            COMPOSE_MODE="docker-compose-bin"
            return
        fi

        if sudo -n docker info >/dev/null 2>&1; then
            COMPOSE_MODE="sudo-docker-compose-bin"
            return
        fi
    fi

    echo "⚠️ Docker requires sudo for this user."
    echo "🔐 Please authenticate once for Docker/Compose commands..."
    sudo -v

    if sudo -n docker info >/dev/null 2>&1 && sudo -n docker compose version >/dev/null 2>&1; then
        COMPOSE_MODE="sudo-docker-compose-plugin"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
        COMPOSE_MODE="sudo-docker-compose-bin"
        return
    fi

    echo "❌ Docker Compose is not available. Install docker-compose-plugin or docker-compose."
    exit 1
}

compose_cmd() {
    case "$COMPOSE_MODE" in
        docker-compose-plugin)
            docker compose "$@"
            ;;
        sudo-docker-compose-plugin)
            sudo docker compose "$@"
            ;;
        docker-compose-bin)
            docker-compose "$@"
            ;;
        sudo-docker-compose-bin)
            sudo docker-compose "$@"
            ;;
        *)
            echo "❌ Compose mode is not initialized."
            exit 1
            ;;
    esac
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_STACK_DIR="$ROOT_DIR/base_stack"
CONFIG_FILE="$ROOT_DIR/configs/.base_stack.conf"

echo "🚀 Starting Odoo Base Stack Setup..."

# --------------------------------------

# Load configuration

# --------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
echo "❌ Missing configuration file: .base_stack.conf"
exit 1
fi

# shellcheck disable=SC1090

source "$CONFIG_FILE"

echo "✔ Loaded configuration:"
echo "   COMPANY_NAME=$COMPANY_NAME"
echo "   ODOO_VERSION=$ODOO_VERSION"

CONF_FILE="${COMPANY_NAME}_odoo${ODOO_VERSION}.conf"
DOCKERFILE="${COMPANY_NAME}_odoo${ODOO_VERSION}.dockerfile"
REQ_FILE="${COMPANY_NAME}_odoo${ODOO_VERSION}_requirements.txt"

resolve_compose_mode

# --------------------------------------

# Step 1: Prepare Docker environment

# --------------------------------------

echo ""
echo "🔧 Step 1: Preparing Docker environment..."
"$ROOT_DIR/scripts/prepare_docker.sh"

# --------------------------------------

# Step 2: Build base Odoo images

# --------------------------------------

echo ""
echo "🏗 Step 2: Building Odoo base images..."
"$ROOT_DIR/scripts/build_odoo_base_images.sh"

# --------------------------------------

# Step 3: Setup base stack files
# --------------------------------------
BASE_STACK_DIR="$ROOT_DIR/base_stack"

echo ""
echo "📁 Step 3: Creating base stack files..."

if [[ -d "$BASE_STACK_DIR" ]]; then
    echo "⚠️ Directory $BASE_STACK_DIR already exists."

    read -p "Do you want a fresh setup? This will overwrite existing files. (y/n): " choice

    case "$choice" in
        y|Y )
            echo "🧹 Removing existing directory..."
            sudo rm -rf "$BASE_STACK_DIR"
            echo "🚀 Creating fresh base stack..."
            "$ROOT_DIR/scripts/setup_base_stack.sh"
            ;;
        n|N )
            echo "✅ Keeping existing base stack. Skipping setup."
            ;;
        * )
            echo "❌ Invalid input. Please run again and choose y or n."
            exit 1
            ;;
    esac
else
    echo "🚀 Directory not found. Creating base stack..."
    "$ROOT_DIR/scripts/setup_base_stack.sh"
fi

# --------------------------------------

# Step 4: Verify required files

# --------------------------------------

echo ""
echo "🔍 Step 4: Verifying base_stack files..."

REQUIRED_FILES=(
"$BASE_STACK_DIR/docker-compose.yml"
"$BASE_STACK_DIR/Caddyfile"
"$BASE_STACK_DIR/$CONF_FILE"
"$BASE_STACK_DIR/$DOCKERFILE"
"$BASE_STACK_DIR/$REQ_FILE"
"$BASE_STACK_DIR/pgadmin/.pgpass"
"$BASE_STACK_DIR/pgadmin/.servers.json"
)

# Wait for required files to be created
WAIT_TIME=30
SLEEP_INTERVAL=2

for file in "${REQUIRED_FILES[@]}"; do
elapsed=0
  while [ ! -f "$file" ]; do
      if [ "$elapsed" -ge "$WAIT_TIME" ]; then
          echo "❌ Timeout waiting for file: $file"
          exit 1
      fi

      echo "⏳ Waiting for $file ..."
      sleep "$SLEEP_INTERVAL"
      elapsed=$((elapsed + SLEEP_INTERVAL))
  done
  echo "✔ Found $file"
done

echo "✔ All required files exist."

# --------------------------------------

# Step 5: Start docker stack

# --------------------------------------

echo ""
echo "🐳 Step 5: Starting base docker stack..."

cd "$BASE_STACK_DIR"

# Check if the compose file exists
if [[ ! -f "$BASE_STACK_DIR/docker-compose.yml" ]]; then
    echo "❌ docker-compose.yml not found in $BASE_STACK_DIR"
    exit 1
fi

# Check if containers from this compose are already running
# shellcheck disable=SC2034
running_containers=$(compose_cmd ps -q)

# Decide to start or restart
if [[ -n "$running_containers" ]]; then
    echo "⚠️ Containers already exist. Restarting..."
    compose_cmd restart
else
    echo "🚀 No existing containers. Starting..."
    compose_cmd up -d
fi
echo ""
echo "✅ Base stack is up!"

echo "🌐 Waiting for base instance to be accessible..."

URL="https://${DOMAIN}/odoo"
HTTP_URL="http://${HOST_IP}:8069"
START_TS=$(date +%s)
NEXT_CHECK_TS=$START_TS

while true; do
    NOW_TS=$(date +%s)
    WAITED=$((NOW_TS-START_TS))

    if (( NOW_TS >= NEXT_CHECK_TS )); then
        if curl -k -L -s --connect-timeout 2 --max-time 4 "$URL" >/dev/null 2>&1 || \
           curl -L -s --connect-timeout 2 --max-time 4 "$HTTP_URL" >/dev/null 2>&1; then
            break
        fi
        NEXT_CHECK_TS=$((NOW_TS+3))
    fi

    printf "\r⏳ Waiting... (%ss)" "$WAITED"
    sleep 1
done

echo
echo "✅ Base instance is accessible."

echo "https://${DOMAIN}/odoo"
echo "Alternatively, access pgAdmin at http://${HOST_IP}:8069"
echo ""
echo ""
echo "🎉 Odoo Stack setup complete!"
echo ""
echo ""

