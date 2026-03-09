#!/bin/bash
set -e

ensure_dependencies() {
    set -e
    echo "🔍 Ensuring requiredfr dependencies and Docker environment..."

    # -----------------------------
    # Ensure git exists
    # -----------------------------
    if ! command -v git >/dev/null 2>&1; then
        echo "❌ git is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y git
        echo "✅ git installed successfully."
    else
        echo "✅ git is already installed."
    fi

    # -----------------------------
    # Ensure unzip exists
    # -----------------------------
    if ! command -v unzip >/dev/null 2>&1; then
        echo "❌ unzip is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y unzip
        echo "✅ unzip installed successfully."
    else
        echo "✅ unzip is already installed."
    fi

    # -----------------------------
    # Ensure inotify-tools exists
    # -----------------------------
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "❌ inotify-tools is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y inotify-tools
        echo "✅ inotify-tools installed successfully."
    else
        echo "✅ inotify-tools is already installed."
    fi

    # -----------------------------
    # Ensure Docker Engine exists
    # -----------------------------
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker Engine is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y docker.io
        echo "✅ Docker Engine installed successfully."
    else
        echo "✅ Docker Engine is already installed."
    fi

    # -----------------------------
    # Ensure Docker Compose plugin
    # -----------------------------
    if ! docker compose version >/dev/null 2>&1; then
        echo "❌ Docker Compose plugin is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
        echo "✅ Docker Compose plugin installed successfully."
    else
        echo "✅ Docker Compose plugin is already installed."
    fi

    # -----------------------------
    # Check Docker daemon
    # -----------------------------
    if ! systemctl is-active --quiet docker; then
        echo "⚠️ Docker daemon is not running. Starting..."
        sudo systemctl start docker
    fi

    echo "✅ Docker daemon running."

    # -----------------------------
    # Check Docker root directory
    # -----------------------------
    DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

    if [ -z "$DOCKER_ROOT" ]; then
        echo "❌ Unable to determine Docker root directory."
        exit 1
    fi

    echo "Docker Root Dir: $DOCKER_ROOT"

    # -----------------------------
    # Ensure Docker tmp directory
    # -----------------------------
    if [ ! -d "$DOCKER_ROOT/tmp" ]; then
        echo "⚠️ Creating Docker tmp directory..."
        sudo mkdir -p "$DOCKER_ROOT/tmp"
        sudo chmod 0711 "$DOCKER_ROOT/tmp"
    fi

    echo "✅ Docker tmp directory ready."

    # -----------------------------
    # Restart Docker to stabilize
    # -----------------------------
    echo "🔄 Restarting Docker service..."
    sudo systemctl restart docker
    sleep 3

    # -----------------------------
    # Test Docker image pull
    # -----------------------------
    echo "📦 Testing Docker image pull..."

    if docker pull hello-world >/dev/null 2>&1; then
        echo "✅ Docker image pull successful."
    else
        echo "❌ Docker image pull failed."
        exit 1
    fi

    echo "🎉 All dependencies and Docker environment are ready."
}

reset_docker_environment() {

    read -p "Do you want a fresh Docker start? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "⏭️ Skipping Docker reset. Continuing with existing environment..."
        return 0
    fi

    echo ""
    echo "⚠️  WARNING: The following actions will be performed:"
    echo "  - Stop ALL running containers"
    echo "  - Remove ALL containers"
    echo "  - Remove ALL Docker images"
    echo "  - Remove ALL volumes"
    echo "  - Remove unused networks"
    echo "  - Run full docker system prune"
    echo ""
    echo "This action cannot be undone."
    echo ""

    read -p "Are you absolutely sure you want to continue? (type 'CONFIRM'): " confirm_final

    if [[ "$confirm_final" != "CONFIRM" ]]; then
        echo "❌ Operation cancelled."
        return 0
    fi

    echo "🛑 Stopping all containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true

    echo "🧹 Removing all containers..."
    docker rm $(docker ps -aq) 2>/dev/null || true

    echo "🗑 Removing all images..."
    docker rmi -f $(docker images -aq) 2>/dev/null || true

    echo "📦 Removing all volumes..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    docker volume prune -f

    echo "🌐 Cleaning unused networks..."
    docker network prune -f

    echo "🧼 Performing full system prune..."
    docker system prune -a --volumes -f

    echo "✅ Docker environment cleaned successfully."
}

ensure_dependencies
reset_docker_environment