#!/bin/bash

# ==========================================================
# SCRIPT: install_package.sh
# ==========================================================
#
# Purpose:
# --------
# Install Python packages into the running Odoo container for
# a specified stack directory.
#
# Usage:
# ------
# ./install_package.sh <stack_directory>
#
# Example:
# --------
# ./install_package.sh demo_stack
#
# Behavior:
# ---------
# 1. Resolve stack directory from project root + input argument
# 2. Detect Odoo service name from docker compose
# 3. Verify the Odoo container is running
# 4. Find a requirements file in the stack root
# 5. Copy requirements file into container as /tmp/requirements.txt
# 6. Run pip install inside container
#
# Requirements:
# -------------
# - Docker and docker compose available
# - Target stack directory must exist under project root
# - Odoo service/container must be running
# - A requirements file matching *requirements*.txt must exist
#
# Notes:
# ------
# - If no requirements file is found, the script exits without error.
# - Package installation uses pip with --break-system-packages.
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

CONTAINER_NAME=$(compose_cmd ps --services | grep odoo | head -n1)

if [[ -z "$CONTAINER_NAME" ]]; then
    echo "❌ No Odoo service found in docker-compose.yml"
    exit 1
fi

echo "✔ Odoo service detected: $CONTAINER_NAME"

CONTAINER_ID=$(compose_cmd ps -q "$CONTAINER_NAME")

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

docker_cmd cp "$REQ_FILE" "$CONTAINER_ID:/tmp/requirements.txt"

docker_cmd exec -it "$CONTAINER_ID" pip install --break-system-packages -r /tmp/requirements.txt

echo "✅ Packages installed successfully"