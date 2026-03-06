#!/bin/bash
set -e

echo "🔍 Checking Docker environment..."

# Check Docker installation
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is not installed."
    exit 1
fi

echo "✅ Docker is installed."

# Check Docker daemon
if ! systemctl is-active --quiet docker; then
    echo "⚠️ Docker daemon is not running. Starting..."
    sudo systemctl start docker
fi

echo "✅ Docker daemon running."

# Check Docker root directory
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

if [ -z "$DOCKER_ROOT" ]; then
    echo "❌ Unable to determine Docker root directory."
    exit 1
fi

echo "Docker Root Dir: $DOCKER_ROOT"

# Ensure tmp directory exists
if [ ! -d "$DOCKER_ROOT/tmp" ]; then
    echo "⚠️ Creating Docker tmp directory..."
    sudo mkdir -p "$DOCKER_ROOT/tmp"
    sudo chmod 0711 "$DOCKER_ROOT/tmp"
fi

echo "✅ Docker tmp directory ready."

# Restart Docker to stabilize environment
echo "🔄 Restarting Docker service..."
sudo systemctl restart docker

sleep 3

# Test pulling a small image
echo "📦 Testing Docker image pull..."

if docker pull hello-world >/dev/null 2>&1; then
    echo "✅ Docker image pull successful."
else
    echo "❌ Docker image pull failed."
    exit 1
fi

echo "🎉 Docker environment is ready."

echo "⚠️  WARNING: This will remove ALL Docker containers, images, volumes, and networks."
echo "This action cannot be undone."

read -p "Do you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "❌ Operation cancelled."
    exit 0
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