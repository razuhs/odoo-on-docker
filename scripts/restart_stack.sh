#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STACK_NAME="$1"

if [[ -z "$STACK_NAME" ]]; then
    echo "❌ Usage: $0 <stack_directory>"
    echo "Example:"
    echo "  ./restart_stack.sh demo_stack"
    exit 1
fi

STACK_DIR="$PROJECT_ROOT/$STACK_NAME"

if [[ ! -d "$STACK_DIR" ]]; then
    echo "❌ Stack directory not found: $STACK_DIR"
    exit 1
fi

cd "$STACK_DIR"

echo "🔎 Detecting Odoo container..."

SERVICE_NAME=$(docker compose ps --services | grep odoo | head -n1)

if [[ -z "$SERVICE_NAME" ]]; then
    echo "❌ No Odoo service found in docker-compose.yml"
    exit 1
fi

CONTAINER_ID=$(docker compose ps -q "$SERVICE_NAME")

if [[ -z "$CONTAINER_ID" ]]; then
    echo "⚠️ Odoo container not running. Starting it..."
    docker compose up -d "$SERVICE_NAME"
else
    echo "🔄 Restarting container: $SERVICE_NAME"
    docker restart "$CONTAINER_ID"
fi

echo "✅ Stack restarted successfully"