#!/bin/bash

# ==========================================================
# SCRIPT: restart_stack.sh
# ==========================================================
#
# Purpose:
# --------
# Restart (or start) the Odoo service container for a given
# stack directory.
#
# Usage:
# ------
# ./restart_stack.sh <stack_directory>
#
# Example:
# --------
# ./restart_stack.sh demo_stack
#
# Behavior:
# ---------
# 1. Resolve stack path from project root and input argument.
# 2. Detect the Odoo service from docker compose services.
# 3. If service container is running: restart it.
# 4. If service container is not running: start it with compose up -d.
#
# Requirements:
# -------------
# - Docker and docker compose available
# - Valid stack directory containing docker-compose.yml
# - Odoo service name in compose output contains "odoo"
#
# Output:
# -------
# - Success message when restart/start completes.
# - Clear error if stack or Odoo service cannot be found.
#
# ==========================================================
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

compose_cmd() {
    if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif sudo docker info >/dev/null 2>&1 && sudo docker compose version >/dev/null 2>&1; then
        sudo docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            docker-compose "$@"
        else
            sudo docker-compose "$@"
        fi
    else
        echo "❌ Docker Compose is not available. Install docker-compose-plugin or docker-compose."
        exit 1
    fi
}

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

SERVICE_NAME=$(compose_cmd ps --services | grep odoo | head -n1)

if [[ -z "$SERVICE_NAME" ]]; then
    echo "❌ No Odoo service found in docker-compose.yml"
    exit 1
fi

CONTAINER_ID=$(compose_cmd ps -q "$SERVICE_NAME")


if [[ -z "$CONTAINER_ID" ]]; then
    echo "⚠️ Odoo container not running. Starting it..."
    compose_cmd up -d "$SERVICE_NAME"
else
    echo "🔄 Restarting container: $SERVICE_NAME"
    docker_cmd restart "$CONTAINER_ID"
fi

echo "✅ Stack restarted successfully"