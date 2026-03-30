#!/bin/bash
set -e

# ==========================================================
# 📘 SCRIPT: generate_test_configs.sh
# ==========================================================
#
# 🚀 Purpose:
# ------------
# Generates TEST configuration files from template patterns.
#
# Differences from template configs:
# - "template" → replaced with "test"
# - TEMPLATE=False (DB will be cloned from template)
#
# ==========================================================


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