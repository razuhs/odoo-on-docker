#!/bin/bash

# build_odoo_base_images.sh
#
# Purpose:
#   Ensure custom Odoo base images exist for versions START_VERSION..END_VERSION.
#
# Behavior:
#   1) Detect missing images named odoo-custom:<version>
#   2) Pull official odoo:<version> for missing versions only
#   3) Build odoo-custom:<version> from Dockerfile.base for missing versions only
#
# Notes:
#   - If all required images exist, the script exits without pulling/building.
#   - Docker CLI access is required.

set -e

DOCKER_USE_SUDO=false

ensure_docker_access_mode() {
    if docker info >/dev/null 2>&1; then
        DOCKER_USE_SUDO=false
        return
    fi

    if sudo -n docker info >/dev/null 2>&1; then
        DOCKER_USE_SUDO=true
        return
    fi

    echo "⚠️ Docker requires sudo for this user."
    echo "🔐 Please authenticate once for Docker commands..."
    sudo -v

    if sudo -n docker info >/dev/null 2>&1; then
        DOCKER_USE_SUDO=true
        return
    fi

    echo "❌ Docker is not accessible. Ensure daemon is running and user has permissions."
    exit 1
}

docker_cmd() {
    if [[ "$DOCKER_USE_SUDO" == true ]]; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START_VERSION=18
END_VERSION=19

ensure_docker_access_mode

echo ""
echo "🔍 Checking for existing Odoo base images (odoo-custom:$START_VERSION–$END_VERSION)..."

missing_images=()

for ((version=START_VERSION; version<=END_VERSION; version++)); do
    if ! docker_cmd images --format "{{.Repository}}:{{.Tag}}" | grep -q "^odoo-custom:$version$"; then
        missing_images+=("$version")
    fi
done

# If all images exist → skip everything
if [[ ${#missing_images[@]} -eq 0 ]]; then
    echo "✅ All required images already exist."
    echo "⏭️ Skipping pull and build."
    exit 0
fi

echo "⚠️ Missing images for versions: ${missing_images[*]}"
echo ""

# Step 1: Pull base images only for missing versions
echo "📥 Pulling base images..."

for version in "${missing_images[@]}"; do
    echo "⬇️ Pulling odoo:$version"
    docker_cmd pull odoo:"$version"
done

# Step 2: Build only missing images
echo ""
echo "🔨 Building custom images..."

for version in "${missing_images[@]}"; do
    echo "-----------------------------------"
    echo "🔨 Building odoo-custom:$version"
    echo "-----------------------------------"

    docker_cmd build \
        --build-arg ODOO_VERSION="$version" \
        -t odoo-custom:"$version" \
        -f "$PROJECT_ROOT/Dockerfile.base" \
        "$PROJECT_ROOT"

    echo "✅ Built odoo-custom:$version"
done

echo ""
echo "🎉 Odoo image setup complete!"