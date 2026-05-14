#!/bin/bash

# ==========================================================
# SCRIPT: prepare_docker.sh
# ==========================================================
#
# Purpose:
# --------
# Prepare Docker on the host machine for this Odoo project by:
# 1) ensuring required packages are installed,
# 2) validating Docker daemon/runtime health,
# 3) optionally performing a hard Docker reset.
#
#
# Usage:
# ------
# ./prepare_docker.sh
#
#
# Main Flow:
# ----------
# 1. ensure_dependencies
#    - apt update
#    - install missing tools (git, unzip, inotify-tools, docker.io)
#    - install Docker Compose plugin if missing
#    - start/restart Docker daemon
#    - verify Docker by pulling hello-world
#
# 2. reset_docker_environment (interactive)
#    - asks for explicit confirmation before destructive operations
#    - optionally preserves Odoo images (odoo:16-19, odoo-custom:16-19)
#    - removes containers, images, volumes, networks, and prunes system
#
#
# Safety and Prompts:
# -------------------
# - Hard reset is NOT run unless user types: yes
# - Final destructive confirmation requires typing: CONFIRM
# - User can choose to preserve Odoo images to avoid rebuild time
#
#
# Requirements:
# -------------
# - Ubuntu/Debian-style package manager (apt-get)
# - sudo privileges
# - Internet access (package installs and docker pull test)
#
# ==========================================================
set -e

# --------------------------------------
# GLOBAL FLAG
# --------------------------------------
KEEP_ODOO_IMAGES=false

# --------------------------------------
# Ensure dependencies
# --------------------------------------
ensure_dependencies() {
    echo "🔍 Ensuring required dependencies and Docker environment..."

    install_if_missing() {
        local cmd="$1"
        local pkg="$2"

        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ $pkg is required but not installed. Installing..."
            sudo apt-get install -y "$pkg"
            echo "✅ $pkg installed successfully."
        else
            echo "✅ $pkg is already installed."
        fi
    }

    echo "📦 Updating package list..."
    sudo apt-get update

    install_if_missing git git
    install_if_missing unzip unzip
    install_if_missing inotifywait inotify-tools
    install_if_missing docker docker.io

    if ! docker compose version >/dev/null 2>&1; then
        echo "❌ Docker Compose plugin missing. Installing..."
        sudo apt-get install -y docker-compose-plugin
        echo "✅ Docker Compose plugin installed."
    else
        echo "✅ Docker Compose plugin is already installed."
    fi

    if ! systemctl is-active --quiet docker; then
        echo "⚠️ Docker daemon not running. Starting..."
        sudo systemctl start docker
    fi

    echo "✅ Docker daemon running."

    DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

    if [[ -z "$DOCKER_ROOT" ]]; then
        echo "❌ Unable to determine Docker root directory."
        exit 1
    fi

    echo "📂 Docker Root Dir: $DOCKER_ROOT"

    if [[ ! -d "$DOCKER_ROOT/tmp" ]]; then
        echo "⚠️ Creating Docker tmp directory..."
        sudo mkdir -p "$DOCKER_ROOT/tmp"
        sudo chmod 0711 "$DOCKER_ROOT/tmp"
    fi

    echo "✅ Docker tmp directory ready."

    echo "🔄 Restarting Docker..."
    sudo systemctl restart docker
    sleep 3

    echo "📦 Testing Docker pull..."
    if docker pull hello-world >/dev/null 2>&1; then
        echo "✅ Docker working correctly."
    else
        echo "❌ Docker pull failed."
        exit 1
    fi

    echo "🎉 Dependencies ready."
}

# --------------------------------------
# Detect Odoo images
# --------------------------------------
handle_odoo_images() {
    echo ""
    echo "🔍 Checking Odoo images (16–19)..."

    local versions=(16 17 18 19)
    local repos=("odoo" "odoo-custom")
    local found=()

    for repo in "${repos[@]}"; do
        for v in "${versions[@]}"; do
            img="${repo}:${v}"
            if docker image inspect "$img" >/dev/null 2>&1; then
                echo "✔ Found: $img"
                found+=("$img")
            fi
        done
    done

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "ℹ️ No Odoo images found."
        KEEP_ODOO_IMAGES=false
        return
    fi

    echo ""
    echo "⚠️ These images are large and time-consuming to rebuild:"
    for img in "${found[@]}"; do
        echo " - $img"
    done

    echo ""
    read -p "👉 Keep these images? (recommended) (y/n): " choice

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        KEEP_ODOO_IMAGES=true
        echo "✅ Will preserve Odoo images."
    else
        KEEP_ODOO_IMAGES=false
        echo "🗑️ Will remove Odoo images."
    fi
}

# --------------------------------------
# Reset Docker
# --------------------------------------
reset_docker_environment() {

    read -p "🔥 Do you want HARD Docker reset? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "⏭️ Skipping Docker reset."
        return
    fi

    echo ""
    echo "⚠️ This will REMOVE:"
    echo " - All containers"
    echo " - All volumes"
    echo " - All networks"
    echo " - Most images"
    echo ""

    read -p "Type 'CONFIRM' to continue: " confirm2

    if [[ "$confirm2" != "CONFIRM" ]]; then
        echo "❌ Cancelled."
        return
    fi

    # Detect images first
    handle_odoo_images

    echo "🛑 Stopping containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true

    echo "🧹 Removing containers..."
    docker rm $(docker ps -aq) 2>/dev/null || true

    echo "🗑 Removing images..."

    if [[ "$KEEP_ODOO_IMAGES" == true ]]; then
        echo "⚠️ Preserving Odoo images..."

        for img in $(docker images -aq); do
            tags=$(docker inspect --format='{{.RepoTags}}' "$img" 2>/dev/null || echo "")

            if echo "$tags" | grep -qE 'odoo:(16|17|18|19)|odoo-custom:(16|17|18|19)'; then
                echo "⏭ Skipping $tags"
            else
                docker rmi -f "$img" 2>/dev/null || true
            fi
        done
    else
        docker rmi -f $(docker images -aq) 2>/dev/null || true
    fi

    echo "📦 Removing volumes..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    docker volume prune -f

    echo "🌐 Cleaning networks..."
    docker network prune -f

    echo "🧼 System prune..."
    docker system prune -a --volumes -f

    echo "✅ Docker reset complete."
}

# --------------------------------------
# Run
# --------------------------------------
ensure_dependencies
reset_docker_environment