#!/bin/bash

set -e

mkdir -p /opt/odoo/server

Pull Odoo versions 16 to 19
for version in 16 17 18 19; do
    echo "Cloning Odoo ${version}..."
    if ! git clone --single-branch --branch ${version}.0 https://github.com/odoo/odoo.git /opt/odoo/server/odoo-${version}; then
        echo "ERROR: Failed to clone Odoo ${version}" >&2
        exit 1
    fi
done

# Pull Odoo Enterprise versions 16 to 19
for version in 16 17 18 19; do
    echo "Cloning Enterprise ${version}..."
    if ! git clone --single-branch --branch ${version}.0 git@github.com:odoo/enterprise.git /opt/odoo/server/enterprise-${version}; then
        echo "ERROR: Failed to clone Enterprise ${version}. Check SSH key and access permissions." >&2
        exit 1
    fi
done



