#!/bin/bash
set -e

START_VERSION=16
END_VERSION=19

echo "Pulling base images first..."

for version in $(seq $START_VERSION $END_VERSION)
do
    docker pull odoo:$version
done

echo "Building custom images..."

for version in $(seq $START_VERSION $END_VERSION)
do
    echo "-----------------------------------"
    echo "Building odoo-custom:$version"
    echo "-----------------------------------"

    docker build \
        --build-arg ODOO_VERSION=$version \
        -t odoo-custom:$version \
        -f Dockerfile.base .

    echo "✅ Built odoo-custom:$version"
done

echo "🎉 All Odoo images built."