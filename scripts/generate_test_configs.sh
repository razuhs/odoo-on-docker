#!/bin/bash

# ==========================================================
# SCRIPT: generate_test_configs.sh
# ==========================================================
#
# Purpose:
# --------
# This script automatically generates test configuration files
# for multiple Odoo versions, editions, and data modes.
#
# It creates ready-to-use config files for test stacks that
# are based on existing template databases.
#
#
# Usage:
# ------
# ./generate_test_configs.sh
#
#
# Output Location:
# ----------------
# All config files are generated inside:
#   configs/
#
#
# Generated Config Pattern:
# -------------------------
# .test<version><edition><data_flag>_stack.conf
#
# Where:
#   <version>      -> Odoo version (18, 19)
#   <edition>      -> ce (Community) / ee (Enterprise)
#   <data_flag>    -> wdd / wodd
#
#
# Naming Breakdown:
# -----------------
# Example:
#   .test19eewdd_stack.conf
#
#   test       -> test instance
#   19         -> Odoo version
#   ee         -> Enterprise edition
#   wdd        -> With demo data
#   wodd       -> Without demo data
#
#
# Generated Variants:
# -------------------
# For each version, the script generates:
#
#   Community Edition (CE):
#     - with demo data     -> ce + wdd
#     - without demo data  -> ce + wodd
#
#   Enterprise Edition (EE):
#     - with demo data     -> ee + wdd
#     - without demo data  -> ee + wodd
#
# Total per version: 4 configs
# Total versions:    4 (16-19)
#
# Total files: 16 configs
#
#
# Each Generated Config Contains:
# -------------------------------
# - DEMO_ODOO_VERSION
# - DEMO_COMPANY_NAME
# - DEMO_DATA
# - DEMO_ODOO_MODULES
# - EDITION
# - TEMPLATE=False
#
#
# Purpose of Generated Configs:
# -----------------------------
# These configs are used to:
#
# 1. Create test stacks from existing templates
#
# 2. Run isolated validation and QA checks
#
# 3. Keep repeatable test environment naming
#
#
# Important Notes:
# ----------------
# - All generated configs have:
#     TEMPLATE=False
#   -> meaning they are normal, runnable test instances
#      (not template DB creators)
#
# - DEMO_DATA flag follows project logic:
#     False -> load demo data
#     True  -> no demo data
#
# - Existing files prompt for overwrite:
#     y = overwrite current file
#     n = skip current file
#     a = overwrite all remaining files
#
#
# Related Scripts:
# ----------------
# - generate_template_configs.sh
#     -> Generate template stack configs
#
# - start_demo_stack.sh
#     -> Create and run stack from config
#
# - remove_stack.sh
#     -> Clean up stack resources
#
# ==========================================================
set -e


# --------------------------------------
# Paths
# --------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/configs"

mkdir -p "$CONFIG_DIR"

# --------------------------------------
# Config
# --------------------------------------
VERSIONS=({18..19})
EDITIONS=(CE EE)

OVERWRITE_ALL=false

echo "🚀 Generating test config files..."

# --------------------------------------
# Function to handle file write
# --------------------------------------
write_file() {
    local file="$1"
    local content="$2"

    if [[ -f "$file" && "$OVERWRITE_ALL" == false ]]; then
        echo "⚠️ File exists: $file"
        read -p "Overwrite? (y/n/a): " choice

        case "$choice" in
            y|Y)
                ;;
            n|N)
                echo "⏭ Skipped: $file"
                return
                ;;
            a|A)
                OVERWRITE_ALL=true
                ;;
            *)
                echo "❌ Invalid choice. Skipping..."
                return
                ;;
        esac
    fi

    echo "$content" > "$file"
    echo "✔ Created $file"
}

# --------------------------------------
# Main loop
# --------------------------------------
for version in "${VERSIONS[@]}"; do
  for edition in "${EDITIONS[@]}"; do

    edition_lower="${edition,,}"

    # --------------------------------------
    # Module selection
    # --------------------------------------
    if [[ "$edition" == "EE" ]]; then
        MODULES="base,web,mail,contacts,crm,sale_management,purchase_stock,stock,hr,project"
    else
        MODULES="base,muk_web_theme,web,mail,contacts,crm,sale_management,purchase_stock,stock,hr,project"
    fi

    # --------------------------------------
    # WITH DEMO DATA → wdd
    # --------------------------------------
    company_name="test${version}${edition_lower}wdd"
    file="$CONFIG_DIR/.${company_name}_stack.conf"

    content=$(cat <<EOF
DEMO_ODOO_VERSION=${version}
DEMO_COMPANY_NAME=${company_name}
DEMO_DATA=False
DEMO_ODOO_MODULES=${MODULES}
EDITION=${edition}
TEMPLATE=False
EOF
)

    write_file "$file" "$content"

    # --------------------------------------
    # WITHOUT DEMO DATA → wodd
    # --------------------------------------
    company_name="test${version}${edition_lower}wodd"
    file="$CONFIG_DIR/.${company_name}_stack.conf"

    content=$(cat <<EOF
DEMO_ODOO_VERSION=${version}
DEMO_COMPANY_NAME=${company_name}
DEMO_DATA=True
DEMO_ODOO_MODULES=${MODULES}
EDITION=${edition}
TEMPLATE=False
EOF
)

    write_file "$file" "$content"

  done
done

echo "✅ All test configs generated."