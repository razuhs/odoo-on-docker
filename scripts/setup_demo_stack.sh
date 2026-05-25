#!/bin/bash

# ==========================================================
# SCRIPT: setup_demo_stack.sh
# ==========================================================
#
# Purpose:
# --------
# Create and configure a demo/test stack from config files,
# then generate all required runtime files for an Odoo container.
#
# Usage:
# ------
# ./setup_demo_stack.sh <demo_config_file> <stack_directory_name>
#
# Example:
# --------
# ./setup_demo_stack.sh .demo19eewdd_stack.conf demo19eewdd_stack
#
# Input files:
# ------------
# - configs/.base_stack.conf
#   Provides shared/global values (DOMAIN, DB_USER, DB_PASS,
#   ODOO_ADMIN_PASS, ENTERPRISE_PATH_<version>, etc.).
#
# - configs/<demo_config_file>
#   Provides stack-specific values (DEMO_ODOO_VERSION,
#   DEMO_COMPANY_NAME, DEMO_DATA, EDITION, TEMPLATE,
#   DEMO_ODOO_MODULES).
#
# Main flow:
# ----------
# 1. Validate and load base + demo config files
# 2. Validate Odoo version range (16-19)
# 3. Resolve edition-specific addons path (EE/CE)
# 4. Create or overwrite stack directory structure
# 5. Generate files:
#    - docker-compose.yml
#    - <company>_odoo<version>.conf
#    - <company>_odoo<version>.dockerfile
#    - <company>_odoo<version>_requirements.txt
#    - caddy-sites/<company>_odoo<version>.caddy
#
# Edition behavior:
# -----------------
# - EE: mounts enterprise addons path + EE custom addons
# - CE: mounts CE custom addons only
#
# TEMPLATE behavior:
# ------------------
# - TEMPLATE=True: first run installs DEMO_ODOO_MODULES
# - TEMPLATE=False: starts database without install step
#
# Side effects:
# -------------
# - May delete existing stack directory when overwrite is confirmed.
# - Writes/overwrites stack and caddy files for the target stack.
#
# Requirements:
# -------------
# - Existing odoo-net Docker network
# - Base stack services already available (db, caddy)
# - Valid custom-addons paths and enterprise path for EE
# - sudo permission for directory ownership/permission updates
#
# ==========================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Function to gather user inputs
# shellcheck disable=SC2120
get_next_available_port() {
    local port_file="$PROJECT_ROOT/.used_ports"
    local start_port=8070
    local port=$start_port

    # Create port tracking file if it doesn't exist
    if [[ ! -f "$port_file" ]]; then
        touch "$port_file"
    fi

    # Find next available port
    while grep -q "^$port$" "$port_file" 2>/dev/null; do
        ((port++))
    done

    # Store the port
    echo "$port" >> "$port_file"
    echo "$port"
}

gather_inputs() {

  BASE_CONFIG_FILE="$PROJECT_ROOT/configs/.base_stack.conf"

  CONFIG_NAME="$1"
  # shellcheck disable=SC2034
  STACK_NAME="$2"

  DEMO_CONFIG_FILE="$PROJECT_ROOT/configs/$CONFIG_NAME"

  # Check base config
  if [[ ! -f "$BASE_CONFIG_FILE" ]]; then
      echo "❌ Base config file not found: $BASE_CONFIG_FILE"
      exit 1
  fi

  # Check demo config
  if [[ ! -f "$DEMO_CONFIG_FILE" ]]; then
      echo "❌ Demo config file not found: $DEMO_CONFIG_FILE"
      exit 1
  fi

  # Load configs
  # shellcheck disable=SC1090
  source "$BASE_CONFIG_FILE"

  # shellcheck disable=SC1090
  source "$DEMO_CONFIG_FILE"

  START=16
  LATEST=19

  odoo_version="${DEMO_ODOO_VERSION:-$LATEST}"

  if ! [[ "$odoo_version" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid ODOO VERSION."
      exit 1
  fi

  if (( odoo_version < START || odoo_version > LATEST )); then
      echo "❌ Version must be between $START and $LATEST"
      exit 1
  fi

  comp_name="${DEMO_COMPANY_NAME// /_}"
  comp_name="${comp_name,,}"

  # shellcheck disable=SC2153
  domain="${comp_name}.${DOMAIN}"

  if [[ "$EDITION" == "EE" ]]; then
      VAR_NAME="ENTERPRISE_PATH_${odoo_version}"
      ent_path=$(eval echo \$"$VAR_NAME")

      if [ -z "$ent_path" ]; then
          echo "❌ Enterprise path for Odoo $odoo_version not found."
          exit 1
      fi

      if [ ! -d "$ent_path" ]; then
          echo "❌ Directory does not exist: $ent_path"
          exit 1
      fi
  elif [[ "$EDITION" == "CE" ]]; then
      ent_path=""
  else
      echo "❌ EDITION must be either 'EE' or 'CE'"
      exit 1
  fi

  # shellcheck disable=SC2153
  db_user="$DB_USER"
  # shellcheck disable=SC2153
  db_pass="$DB_PASS"

  odoo_conf_admin_pass="$ODOO_ADMIN_PASS"
  # shellcheck disable=SC2153
  demo_data="$DEMO_DATA"

  # Get next available port for this stack
  odoo_port=$(get_next_available_port)
}

create_directory_and_files() {

    echo "Creating demo stack directories..."

    STACK_DIR="$PROJECT_ROOT/${STACK_NAME}"

    if [[ -d "$STACK_DIR" ]]; then
        echo "⚠️ Stack directory already exists: $STACK_DIR"
        # shellcheck disable=SC2162
        read -p "Do you want to overwrite it? (y/n): " choice

        if [[ "$choice" != "y" ]]; then
            echo "Aborting."
            exit 1
        fi

        sudo rm -rf "$STACK_DIR"
    fi

    mkdir -p "$STACK_DIR"
    echo "stack directory: $STACK_DIR"
    sudo chown -R 1000:1000 "$STACK_DIR"
    sudo chmod -R 775 "$STACK_DIR"

    # Ensure shared log directories exist with predictable permissions.
    mkdir -p "$PROJECT_ROOT/logs/odoo-logs" "$PROJECT_ROOT/logs/caddy-logs"
    sudo chown -R 101:101 "$PROJECT_ROOT/logs/odoo-logs"
    sudo chmod -R 775 "$PROJECT_ROOT/logs/odoo-logs"
    sudo chown -R 1000:1000 "$PROJECT_ROOT/logs/caddy-logs"
    sudo chmod -R 775 "$PROJECT_ROOT/logs/caddy-logs"
    sudo find "$PROJECT_ROOT/logs/caddy-logs" -type d -exec chmod 2775 {} \;

    touch "$STACK_DIR/${comp_name}_odoo${odoo_version}.conf"
    touch "$STACK_DIR/${comp_name}_odoo${odoo_version}.dockerfile"
    touch "$STACK_DIR/docker-compose.yml"
    touch "$STACK_DIR/${comp_name}_odoo${odoo_version}_requirements.txt"
    touch "$PROJECT_ROOT/caddy-sites/${comp_name}_odoo${odoo_version}.caddy"

    echo "✅ Demo stack files created."
}

write_docker_compose() {

# --------------------------------------
# Volume block
# --------------------------------------
if [[ "$EDITION" == "EE" ]]; then
    volume_block="- ../custom-addons/odoo-${odoo_version}ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-${odoo_version}-ee"
elif [[ "$EDITION" == "CE" ]]; then
    volume_block="- ../custom-addons/odoo-${odoo_version}ce-custom-addons:/mnt/extra-addons"
else
    echo "❌ EDITION must be either 'EE' or 'CE'"
    exit 1
fi

# --------------------------------------
# TEMPLATE flag default
# --------------------------------------
TEMPLATE="${TEMPLATE:-False}"

# --------------------------------------
# Build Odoo command dynamically
# --------------------------------------
if [[ "$TEMPLATE" == "True" ]]; then
    ODOO_COMMAND="odoo -d ${comp_name}-odoo${odoo_version}-db -i ${DEMO_ODOO_MODULES} --config=/etc/odoo/${comp_name}_odoo${odoo_version}.conf"
else
    ODOO_COMMAND="odoo -d ${comp_name}-odoo${odoo_version}-db --config=/etc/odoo/${comp_name}_odoo${odoo_version}.conf"
fi
# --------------------------------------
# Write docker-compose
# --------------------------------------
cat <<EOF > "$STACK_DIR/docker-compose.yml"
services:
  ${comp_name}_odoo${odoo_version}:
    build:
      context: .
      dockerfile: ${comp_name}_odoo${odoo_version}.dockerfile
    container_name: ${comp_name}_odoo${odoo_version}
    restart: unless-stopped
    environment:
      - HOST=db
      - USER=${db_user}
      - PASSWORD=${db_pass}
    volumes:
      ${volume_block}
      - ./${comp_name}_odoo${odoo_version}.conf:/etc/odoo/${comp_name}_odoo${odoo_version}.conf
      - odoo_db_data:/var/lib/odoo
      - ../logs/odoo-logs:/var/log/odoo
    ports:
      - "${odoo_port}:8069"
    command: >
      ${ODOO_COMMAND}
    
    networks:
      - odoo-net

networks:
  odoo-net:
    external: true

volumes:
  odoo_db_data:
EOF

echo "✅ docker-compose.yml written successfully."
}

write_odoo_conf() {

if [[ "$EDITION" == "EE" ]]; then
    addons_path="/mnt/odoo-${odoo_version}-ee,/mnt/extra-addons"
else
    addons_path="/mnt/extra-addons"
fi

cat <<EOF > "$STACK_DIR/${comp_name}_odoo${odoo_version}.conf"
[options]
admin_passwd = ${odoo_conf_admin_pass}
db_user = ${db_user}
db_password = ${db_pass}
db_host = db
db_port = 5432
addons_path = ${addons_path}
db_filter = ^${comp_name}-odoo${odoo_version}-db$
proxy_mode = True
logfile = /var/log/odoo/${comp_name}_odoo${odoo_version}.log
without_demo = ${demo_data}
EOF

echo "✅ Odoo config written."
}

write_dockerfile_ext() {

cat <<EOF > "$STACK_DIR/${comp_name}_odoo${odoo_version}.dockerfile"
FROM odoo-custom:${odoo_version}

USER root

COPY ${comp_name}_odoo${odoo_version}_requirements.txt /tmp/req.txt

RUN if [ ${odoo_version} -ge 18 ]; then \\
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \\
else \\
    pip install --ignore-installed -r /tmp/req.txt; \\
fi

USER odoo
EOF

echo "✅ Dockerfile written."
}

write_dockerfile() {
cat <<EOF > "$STACK_DIR/${comp_name}_odoo${odoo_version}.dockerfile"
FROM odoo-custom:${odoo_version}

USER odoo
EOF
echo "✅ Dockerfile written."
}

write_caddy_site_file() {

cat <<EOF > "$PROJECT_ROOT/caddy-sites/${comp_name}_odoo${odoo_version}.caddy"
${domain} {
    reverse_proxy ${comp_name}_odoo${odoo_version}:8069
    log {
        output file /caddy-logs/${comp_name}_odoo${odoo_version}_access.log {
            mode 0644
        }
    }
}
EOF

echo "✅ Caddy site file written."
}

write_requirements_ext() {

cat <<EOF > "$STACK_DIR/${comp_name}_odoo${odoo_version}_requirements.txt"
pydantic==2.10.6
pydantic-core==2.27.2
email_validator==2.2.0
phonenumbers==9.0.12
EOF

echo "✅ requirements.txt written."
}

write_requirements() {

cat <<EOF > "$STACK_DIR/${comp_name}_odoo${odoo_version}_requirements.txt"
EOF

echo "✅ requirements.txt written."
}


gather_inputs "$@"
create_directory_and_files
write_requirements
write_docker_compose
write_dockerfile
write_odoo_conf
write_caddy_site_file