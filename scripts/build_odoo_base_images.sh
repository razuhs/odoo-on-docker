#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START_VERSION=16
END_VERSION=19

echo ""
echo "🔍 Checking for existing Odoo base images (odoo-custom:$START_VERSION–$END_VERSION)..."

missing_images=()

for ((version=START_VERSION; version<=END_VERSION; version++)); do
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^odoo-custom:$version$"; then
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
    docker pull odoo:"$version"
done

# Step 2: Build only missing images
echo ""
echo "🔨 Building custom images..."

for version in "${missing_images[@]}"; do
    echo "-----------------------------------"
    echo "🔨 Building odoo-custom:$version"
    echo "-----------------------------------"

    docker build \
        --build-arg ODOO_VERSION="$version" \
        -t odoo-custom:"$version" \
        -f "$PROJECT_ROOT/Dockerfile.base" \
        "$PROJECT_ROOT"

    echo "✅ Built odoo-custom:$version"
done

echo ""
echo "🎉 Odoo image setup complete!"