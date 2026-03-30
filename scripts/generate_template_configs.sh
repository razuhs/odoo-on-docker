#!/bin/bash
# ==========================================================
# 📘 SCRIPT: generate_template_configs.sh
# ==========================================================
#
# 🚀 Purpose:
# ------------
# This script automatically generates template configuration
# files for multiple Odoo versions, editions, and data modes.
#
# It creates ready-to-use config files for building template
# databases across different combinations.
#
#
# 🧾 Usage:
# ----------
# ./generate_template_configs.sh
#
#
# 📂 Output Location:
# -------------------
# All config files are generated inside:
#   configs/
#
#
# 📦 Generated Config Pattern:
# ----------------------------
# .template<version><edition><data_flag>_stack.conf
#
# Where:
#   <version>      → Odoo version (16, 17, 18, 19)
#   <edition>      → ce (Community) / ee (Enterprise)
#   <data_flag>    → wdd / wodd
#
#
# 🧠 Naming Breakdown:
# --------------------
# Example:
#   .template19eewdd_stack.conf
#
#   template   → template instance
#   19         → Odoo version
#   ee         → Enterprise edition
#   wdd        → With demo data
#   wodd       → Without demo data
#
#
# 🔁 Generated Variants:
# ----------------------
# For each version, the script generates:
#
#   Community Edition (CE):
#     - with demo data     → ce + wdd
#     - without demo data  → ce + wodd
#
#   Enterprise Edition (EE):
#     - with demo data     → ee + wdd
#     - without demo data  → ee + wodd
#
# Total per version: 4 configs
# Total versions:    4 (16–19)
#
# Total files: 16 configs
#
#
# ⚙️ Each Generated Config Contains:
# ----------------------------------
# - DEMO_ODOO_VERSION
# - DEMO_COMPANY_NAME
# - DEMO_DATA
# - DEMO_ODOO_MODULES
# - EDITION
# - TEMPLATE=True
#
#
# 🎯 Purpose of Generated Configs:
# --------------------------------
# These configs are used to:
#
# 1. Create template stacks:
#      ./start_demo_stack.sh .templateXX...conf
#
# 2. Build template databases:
#      ./make_template_db.sh <stack_name>
#
# 3. Serve as base for fast cloning of new instances
#
#
# ⚠️ Important Notes:
# -------------------
# - All generated configs have:
#     TEMPLATE=True
#   → meaning they are intended ONLY for template creation
#
# - These configs should NOT be used for normal instances
#
# - DEMO_DATA flag follows project logic:
#     False → load demo data
#     True  → no demo data
#
#
# 🔗 Related Scripts:
# -------------------
# - start_demo_stack.sh
#     → Create and run stack from config
#
# - make_template_db.sh
#     → Convert DB into template
#
# - remove_stack.sh
#     → Clean up stack resources
#
#
# 💡 Tip:
# --------
# After generating configs, you can batch-create templates:
#
#   for f in configs/.template*.conf; do
#       ./start_demo_stack.sh "$(basename "$f")"
#   done
#
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
VERSIONS=({16..19})
EDITIONS=(CE EE)

OVERWRITE_ALL=false

echo "🚀 Generating template config files..."

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
    company_name="template${version}${edition_lower}wdd"
    file="$CONFIG_DIR/.${company_name}_stack.conf"

    content=$(cat <<EOF
DEMO_ODOO_VERSION=${version}
DEMO_COMPANY_NAME=${company_name}
DEMO_DATA=False
DEMO_ODOO_MODULES=${MODULES}
EDITION=${edition}
TEMPLATE=True
EOF
)

    write_file "$file" "$content"

    # --------------------------------------
    # WITHOUT DEMO DATA → wodd
    # --------------------------------------
    company_name="template${version}${edition_lower}wodd"
    file="$CONFIG_DIR/.${company_name}_stack.conf"

    content=$(cat <<EOF
DEMO_ODOO_VERSION=${version}
DEMO_COMPANY_NAME=${company_name}
DEMO_DATA=True
DEMO_ODOO_MODULES=${MODULES}
EDITION=${edition}
TEMPLATE=True
EOF
)

    write_file "$file" "$content"

  done
done

echo "✅ All template configs generated."