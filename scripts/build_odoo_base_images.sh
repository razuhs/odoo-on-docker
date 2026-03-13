#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START_VERSION=16
END_VERSION=19

echo ""
read -p "Do you already have the Odoo base images built (odoo-custom:16–19)? (yes/no): " confirm

if [[ "$confirm" == "yes" || "$confirm" == "y" ]]; then
    echo "⏭️ Skipping base image pull and build. Using existing images."
    exit 0
fi

echo "📥 Pulling base images first..."

for version in $(seq $START_VERSION $END_VERSION); do
    docker pull odoo:"$version"
done

echo ""
echo "🔨 Building custom images..."

for version in $(seq $START_VERSION $END_VERSION); do
    echo "-----------------------------------"
    echo "Building odoo-custom:$version"
    echo "-----------------------------------"

    docker build \
    --build-arg ODOO_VERSION="$version" \
    -t odoo-custom:"$version" \
    -f "$PROJECT_ROOT/Dockerfile.base" \
    "$PROJECT_ROOT"

    echo "✅ Built odoo-custom:$version"
done

echo ""
echo "🎉 All Odoo images built."