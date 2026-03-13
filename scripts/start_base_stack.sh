#!/bin/bash
set -e

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

echo ""
echo "📁 Step 3: Creating base stack files..."
"$ROOT_DIR/scripts/setup_base_stack.sh"

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

docker compose up -d

echo ""
echo "✅ Base stack started successfully!"
echo ""
echo "Running containers:"
docker ps
