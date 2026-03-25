#!/bin/bash
set -e

# 📁 Paths
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/configs"
SCRIPT="$PROJECT_ROOT/scripts/start_demo_stack.sh"

# ⚙️ Config
VERSIONS=({18..19})
EDITIONS=(CE EE)

mkdir -p "$CONFIG_DIR"

# =========================================================
# 🔧 Function: Wait for Odoo container to be ready
# =========================================================
wait_for_odoo() {
  local config_file="$1"

  # load config
  # shellcheck disable=SC1090
  source "$CONFIG_DIR/$config_file"

  odoo_version="${DEMO_ODOO_VERSION}"
  comp_name="${DEMO_COMPANY_NAME// /_}"
  comp_name="${comp_name,,}"

  container_name="${comp_name}_odoo${odoo_version}"

  echo "⏳ Waiting for container: $container_name"

  # wait until container exists
  until docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; do
    sleep 2
  done

  # wait until Odoo is ready
  until docker logs "$container_name" 2>&1 | grep -q "HTTP service (werkzeug) running"; do
    sleep 3
  done

  echo "✅ Odoo ready: $container_name"
}

# =========================================================
# 🚀 Step 1: Generate config files
# =========================================================
echo "🚀 Generating template config files..."

for version in "${VERSIONS[@]}"; do
  for edition in "${EDITIONS[@]}"; do

    edition_lower=$(echo "$edition" | tr '[:upper:]' '[:lower:]')

    for demo_flag in False True; do

      if [ "$demo_flag" = "True" ]; then
        suffix="wodd"
      else
        suffix="wdd"
      fi

      company_name="tmpl_${version}${edition_lower}_${suffix}"
      file="$CONFIG_DIR/.${company_name}_stack.conf"

      cat <<EOF > "$file"
DEMO_ODOO_VERSION=${version}
DEMO_COMPANY_NAME=${company_name}
DEMO_DATA=${demo_flag}
DEMO_ODOO_MODULES=base,web,mail,contacts,crm,sale_management,purchase_stock,stock,account_accountant
EDITION=${edition}
EOF

      echo "✔ Created $file"

    done
  done
done

# =========================================================
# 🚀 Step 2: Run stack setup sequentially
# =========================================================
echo ""
echo "🚀 Starting template stack creation..."

shopt -s nullglob

for config in "$CONFIG_DIR"/.tmpl_*.conf; do
    config_name="$(basename "$config")"

    echo ""
    echo "⚙ Running stack setup for: $config_name"

    # 🔥 Run your stack script
    "$SCRIPT" "$config_name"

    # ✅ Wait properly (instead of sleep)
    wait_for_odoo "$config_name"

    echo "✔ Completed: $config_name"

done

shopt -u nullglob

echo ""
echo "✅ All template stacks created successfully."