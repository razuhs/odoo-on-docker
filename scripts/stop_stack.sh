#!/bin/bash

# ==========================================================
# SCRIPT: stop_stack.sh
# ==========================================================
#
# Purpose:
# --------
# Stop the running Odoo container for a specified stack directory.
#
# Usage:
# ------
# ./stop_stack.sh <stack_directory>
#
# Example:
# --------
# ./stop_stack.sh demo_stack
#
# Behavior:
# ---------
# 1. Resolve stack directory from project root.
# 2. Detect Odoo service from docker compose.
# 3. Check whether its container is running.
# 4. Stop the container if running.
#
# Output:
# -------
# - Success message when container is stopped.
# - Informational message if container is already stopped.
# - Error when stack directory or Odoo service is missing.
#
# Requirements:
# -------------
# - Docker and docker compose installed
# - Valid stack directory containing docker-compose.yml
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
    echo "  ./stop_stack.sh demo_stack"
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
    echo "⚠️ Odoo container is not running."
    exit 0
fi

echo "🛑 Stopping container: $SERVICE_NAME"

docker_cmd stop "$CONTAINER_ID"

echo "✅ Stack stopped successfully"