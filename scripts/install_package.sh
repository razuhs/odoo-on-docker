#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STACK_NAME="$1"

if [[ -z "$STACK_NAME" ]]; then
    echo "❌ Usage: $0 <stack_directory>"
    echo "Example:"
    echo "  ./install_package.sh demo_stack"
    exit 1
fi

STACK_DIR="$PROJECT_ROOT/$STACK_NAME"

if [[ ! -d "$STACK_DIR" ]]; then
    echo "❌ Stack directory not found: $STACK_DIR"
    exit 1
fi

cd "$STACK_DIR"

echo "🔎 Detecting Odoo container..."

CONTAINER_NAME=$(docker compose ps --services | grep odoo | head -n1)

if [[ -z "$CONTAINER_NAME" ]]; then
    echo "❌ No Odoo service found in docker-compose.yml"
    exit 1
fi

echo "✔ Odoo service detected: $CONTAINER_NAME"

CONTAINER_ID=$(docker compose ps -q "$CONTAINER_NAME")

if [[ -z "$CONTAINER_ID" ]]; then
    echo "❌ Container not running"
    exit 1
fi

REQ_FILE=$(find "$STACK_DIR" -maxdepth 1 -name "*requirements*.txt" | head -n1)

if [[ -z "$REQ_FILE" ]]; then
    echo "⚠️ No requirements file found"
    exit 0
fi

echo "📦 Installing packages from $REQ_FILE"

docker cp "$REQ_FILE" "$CONTAINER_ID:/tmp/requirements.txt"

docker exec -it "$CONTAINER_ID" pip install --break-system-packages -r /tmp/requirements.txt

echo "✅ Packages installed successfully"