#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STACK_NAME="$1"

if [[ -z "$STACK_NAME" ]]; then
echo "❌ Usage: $0 <stack_directory>"
echo "Example:"
echo "  ./run_demo_stack.sh demo_stack"
exit 1
fi

STACK_DIR="$PROJECT_ROOT/$STACK_NAME"

if [[ ! -d "$STACK_DIR" ]]; then
echo "❌ Stack directory not found: $STACK_DIR"
exit 1
fi

if [[ ! -f "$STACK_DIR/docker-compose.yml" ]]; then
echo "❌ docker-compose.yml not found in $STACK_DIR"
exit 1
fi

echo "🚀 Starting stack: $STACK_NAME"

cd "$STACK_DIR"

docker compose up -d

echo "✅ Stack started successfully"

echo "🔄 Restarting Caddy proxy..."
docker restart caddy-proxy

echo "✅ Caddy restarted successfully"