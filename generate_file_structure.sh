#!/bin/bash
set -euo pipefail
# a test comment
BASE_DIR="$(pwd)"
PARENT_DIR="$BASE_DIR/custom-addons"
START=16

# Ensure git exists
command -v git >/dev/null 2>&1 || {
    echo "❌ git is required but not installed.";
    exit 1;
}
# Ensure unzip is installed
command -v unzip >/dev/null 2>&1 || {
    echo "❌ unzip is required but not installed.";
    exit 1;
}

# Detect latest Odoo version
LATEST=$(
  git ls-remote --heads https://github.com/odoo/odoo.git \
  | grep -E 'refs/heads/[0-9]+\.[0-9]+$' \
  | sed 's#.*/##' \
  | sort -V \
  | tail -1 \
  | cut -d'.' -f1
).

echo "Latest Odoo detected: $LATEST"

echo "Available Odoo versions: $START to $LATEST"
read -p "Enter base/controller Odoo version: " base_version

# Validate numeric input
if ! [[ "$base_version" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid version. Must be a number."
    exit 1
fi

# Validate range
if (( base_version < START || base_version > LATEST )); then
    echo "❌ Version must be between $START and $LATEST"
    exit 1
fi

echo "Base/controller version set to: $base_version"

# Company Name
echo "Enter company name (spaces will be converted to _):"
read -r comp_name

# Convert spaces to underscores
comp_name="${comp_name// /_}"

# Optional: convert to lowercase
comp_name="${comp_name,,}"

echo "Company name set to: $comp_name"

# Domain Name
echo "Enter domain name (e.g. example.com):"
read -r domain

# Basic domain validation (optional but recommended)
if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "❌ Invalid domain format."
    exit 1
fi

echo "Domain set to: $domain"

# Enterprise Addons Path
read -r -p "Enter Odoo ${base_version}.0 enterprise addons parent path (e.g. /opt/odoo/enterprise/${base_version}.0): " ent_path
# Validate path exists
if [ ! -d "$ent_path" ]; then
    echo "❌ Directory does not exist: $ent_path"
    exit 1
fi

echo "Enterprise addons path set to: $ent_path"


# Handle parent directory safely
if [ -d "$PARENT_DIR" ]; then
    read -p "Directory $PARENT_DIR exists. Delete and recreate? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    rm -rf "$PARENT_DIR"
fi

mkdir -p "$PARENT_DIR"

types=("ee" "ce")
# create directory for custom-addons used by every version of odoo
for ((v=START; v<=LATEST; v++)); do
    for t in "${types[@]}"; do
        mkdir -p "$PARENT_DIR/odoo-${v}${t}-custom-addons"
    done
done

echo "✅ Custom-Addons Directory structure created successfully."
# extract theme addons on every community-addons directory
echo "📦 Extracting muk_web_theme.zip..."
unzip -q muk_web_theme.zip -d muk_tmp

for ((v=START; v<=LATEST; v++)); do
    TARGET_DIR="$PARENT_DIR/odoo-${v}ce-custom-addons"

    # Find correct version zip
    INNER_ZIP=$(find muk_tmp -type f -name "muk_web_theme-${v}.0.*.zip" | head -n 1)

    if [ -z "$INNER_ZIP" ]; then
        echo "⚠️ No theme found for Odoo $v"
        continue
    fi

    echo "📦 Installing theme for Odoo $v"
    unzip -q "$INNER_ZIP" -d "$TARGET_DIR"
    echo "✅ Installed into $TARGET_DIR"
done

# Cleanup
rm -rf muk_tmp

echo "🎉 Theme extraction for community edition completed."

rm -rf conf dockerfile pgadmin
mkdir -p conf dockerfile pgadmin
touch "conf/${comp_name}.conf" "pgadmin/.pgpass" "pgadmin/.servers.json"
touch "dockerfile/odoo-admin-${base_version}.dockerfile"
touch start.txt stop.txt install.txt
