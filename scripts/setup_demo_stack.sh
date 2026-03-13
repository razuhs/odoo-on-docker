#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Function to gather user inputs
# shellcheck disable=SC2120
gather_inputs() {

  BASE_CONFIG_FILE="$PROJECT_ROOT/configs/.base_stack.conf"
  DEMO_CONFIG_FILE="$PROJECT_ROOT/configs/.demo_stack.conf"
  DEMO_CONFIG_FILE="${1:-.demo_stack.conf}"
  DEMO_CONFIG_FILE="$PROJECT_ROOT/configs/$DEMO_CONFIG_FILE"

  if [ ! -f "$BASE_CONFIG_FILE" ]; then
      echo "❌ Base config file $BASE_CONFIG_FILE not found."
      exit 1
  fi

  if [ ! -f "$DEMO_CONFIG_FILE" ]; then
      echo "❌ Demo config file $DEMO_CONFIG_FILE not found."
      exit 1
  fi

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
}

create_directory_and_files() {

    echo "Creating demo stack directories..."

    STACK_DIR="$PROJECT_ROOT/${comp_name}_stack"

    if [[ -d "$STACK_DIR" ]]; then
        echo "⚠️ Stack directory already exists: $STACK_DIR"
        # shellcheck disable=SC2162
        read -p "Do you want to delete and recreate it? (y/n): " choice

        if [[ "$choice" != "y" ]]; then
            echo "Aborting."
            exit 1
        fi

        sudo rm -rf "$STACK_DIR"
    fi

    mkdir -p "$STACK_DIR"

    sudo chown -R 1000:1000 "$PROJECT_ROOT/${comp_name}_stack"
    sudo chmod -R 775 "$PROJECT_ROOT/${comp_name}_stack"

    touch "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}.conf"
    touch "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}.dockerfile"
    touch "$PROJECT_ROOT/${comp_name}_stack/docker-compose.yml"
    touch "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}_requirements.txt"

    touch "$PROJECT_ROOT/caddy-sites/${comp_name}_odoo${odoo_version}.caddy"

    echo "✅ Demo stack files created."
}

write_docker_compose() {

if [[ "$EDITION" == "EE" ]]; then
    volume_block="- ../custom-addons/odoo-${odoo_version}ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-${odoo_version}-ee"
elif [[ "$EDITION" == "CE" ]]; then
    volume_block="- ../custom-addons/odoo-${odoo_version}ce-custom-addons:/mnt/extra-addons"
else
    echo "❌ EDITION must be either 'EE' or 'CE'"
    exit 1
fi

cat <<EOF > "$PROJECT_ROOT/${comp_name}_stack/docker-compose.yml"
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
    command: >
      odoo -d ${comp_name}-odoo${odoo_version}-db -i ${DEMO_ODOO_MODULES} --config=/etc/odoo/${comp_name}_odoo${odoo_version}.conf
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

cat <<EOF > "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}.conf"
[options]
admin_passwd = ${odoo_conf_admin_pass}
db_user = ${db_user}
db_password = ${db_pass}
db_host = db
db_port = 5432
addons_path = ${addons_path}
db_filter = ^${comp_name}_odoo${odoo_version}_db$
proxy_mode = True
logfile = /var/log/odoo/${comp_name}_odoo${odoo_version}.log
without_demo = ${demo_data}
EOF

echo "✅ Odoo config written."
}

write_dockerfile() {

cat <<EOF > "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}.dockerfile"
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

write_caddy_site_file() {

cat <<EOF > "$PROJECT_ROOT/caddy-sites/${comp_name}_odoo${odoo_version}.caddy"
${domain} {
    reverse_proxy ${comp_name}_odoo${odoo_version}:8069
    log {
        output file /caddy-logs/${comp_name}_odoo${odoo_version}_access.log
    }
}
EOF

echo "✅ Caddy site file written."
}

write_requirements() {

cat <<EOF > "$PROJECT_ROOT/${comp_name}_stack/${comp_name}_odoo${odoo_version}_requirements.txt"
pydantic==2.10.6
pydantic-core==2.27.2
email_validator==2.2.0
phonenumbers==9.0.12
EOF

echo "✅ requirements.txt written."
}

gather_inputs
create_directory_and_files
write_requirements
write_docker_compose
write_dockerfile
write_odoo_conf
write_caddy_site_file