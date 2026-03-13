#!/bin/bash
set -euo pipefail

custom_addons_dir="$(cd "$(dirname "$0")/.." && pwd)/custom-addons"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sudo rm -rf "$PROJECT_ROOT/base_stack" "$PROJECT_ROOT/custom-addons" "$PROJECT_ROOT/logs" "$PROJECT_ROOT/caddy-sites" "$PROJECT_ROOT/demo_stack"

# Function to .gather user inputs
gather_inputs() {

  CONFIG_FILE="$PROJECT_ROOT/configs/.base_stack.conf"

  if [ ! -f "$CONFIG_FILE" ]; then
      echo "❌ Config file $CONFIG_FILE not found."
      exit 1
  fi

  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  START=16
  LATEST=19

  odoo_version="${ODOO_VERSION:-$LATEST}"

  # Validate numeric
  if ! [[ "$odoo_version" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid odoo version."
      exit 1
  fi

  if (( odoo_version < START || odoo_version > LATEST )); then
      echo "❌ Version must be between $START and $LATEST"
      exit 1
  fi

  comp_name="${COMPANY_NAME// /_}"
  comp_name="${comp_name,,}"

  domain="$DOMAIN"

  VAR_NAME="ENTERPRISE_PATH_${odoo_version}"
  ent_path="${!VAR_NAME}"

  if [ -z "$ent_path" ]; then
      echo "❌ Enterprise path for Odoo $odoo_version not found."
      exit 1
  fi

  if [ ! -d "$ent_path" ]; then
      echo "❌ Directory does not exist: $ent_path"
      exit 1
  fi

  db_user="$DB_USER"
  db_pass="$DB_PASS"

  pg_user="$PGADMIN_EMAIL"
  pg_pass="$PGADMIN_PASS"

  odoo_conf_admin_pass="$ODOO_ADMIN_PASS"
  demo_data="$LOAD_DEMO_DATA"

  # Ensure DB user exists
  if id "$db_user" >/dev/null 2>&1; then
      echo "✅ User '$db_user' already exists."
  else
      echo "⚠️ User '$db_user' does not exist. Creating..."
      sudo useradd -m -s /bin/bash "$db_user"
  fi

  echo ""
  echo "📦 Odoo Stack Configuration"
  echo "--------------------------------"
  echo "Base/controller version : $odoo_version"
  echo "Company name            : $comp_name"
  echo "Domain                  : $domain"
  echo "Enterprise addons path  : $ent_path"
  echo "DB user                 : $db_user"
  echo "PG Admin email          : $pg_user"
  echo "--------------------------------"
  echo "✅ Configuration loaded successfully"
}
# create custom-addons directories for every version of odoo
create_custom_addons_directories() {
    echo "Creating file and directory structure..."
    mkdir -p "$custom_addons_dir"

    types=("ee" "ce")
    # create directory for custom-addons used by every version of odoo
    for ((v=START; v<=LATEST; v++)); do
        for t in "${types[@]}"; do
            mkdir -p "$custom_addons_dir/odoo-${v}${t}-custom-addons"
        done
    done

    echo "✅ Custom-Addons Directory structure created successfully."
}


# extract theme addons on every community-addons directory
extract_theme_for_community() {
echo "📦 Extracting muk_web_theme.zip..."
unzip -q "$PROJECT_ROOT/muk_web_theme.zip" -d "$PROJECT_ROOT/muk_tmp"

for ((v=START; v<=LATEST; v++)); do
    TARGET_DIR="$custom_addons_dir/odoo-${v}ce-custom-addons"

    # Find correct version zip
    INNER_ZIP=$(find "$PROJECT_ROOT/muk_tmp" -type f -name "muk_web_theme-${v}.0.*.zip" | head -n 1)

    if [ -z "$INNER_ZIP" ]; then
        echo "⚠️ No theme found for Odoo $v"
        continue
    fi

    echo "📦 Copying Extracted Theme Module For Odoo $v"
    unzip -q "$INNER_ZIP" -d "$TARGET_DIR"
    echo "✅ Copied into $TARGET_DIR"
done

# Cleanup.
echo "Cleaning Up Extracted Theme Module ..."
rm -rf "$PROJECT_ROOT/muk_tmp"
}

# Create Docker-related files and directories
create_directory_and_files() {

    echo "Creating Docker-related files and directories..."
    # Create main project log & caddy-sites directories
    mkdir -p "$PROJECT_ROOT/base_stack"
    mkdir -p "$PROJECT_ROOT/caddy-sites"
    mkdir -p "$PROJECT_ROOT/logs/odoo-logs" "$PROJECT_ROOT/logs/caddy-logs"

    # Set ownership for project files (host user)
    sudo chown -R 1000:1000 "$PROJECT_ROOT/base_stack"
    sudo chmod -R 775 "$PROJECT_ROOT/base_stack"

    # Set permissions for Odoo logs (Odoo container UID 101)
    sudo chown -R 101:101 "$PROJECT_ROOT/logs/odoo-logs"
    sudo chmod -R 775 "$PROJECT_ROOT/logs/odoo-logs"

    # Set permissions for Caddy logs (host user UID 1000)
    sudo chown -R 1000:1000 "$PROJECT_ROOT/logs/caddy-logs"
    sudo chmod -R 775 "$PROJECT_ROOT/logs/caddy-logs"

    # Set permissions for caddy-sites (host user UID 1000)
    sudo chown -R 1000:1000 "$PROJECT_ROOT/caddy-sites"
    sudo chmod -R 775 "$PROJECT_ROOT/caddy-sites"


    # Create Odoo configuration file
    touch "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}.conf"

    # Create Dockerfile for the specific Odoo version
    touch "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}.dockerfile"

    # Create caddy-site-file
    touch "$PROJECT_ROOT/caddy-sites/base_stack_${comp_name}_odoo${odoo_version}.caddy"

    # Create pgAdmin directory and required configuration files
    mkdir -p "$PROJECT_ROOT/base_stack/pgadmin"
    touch "$PROJECT_ROOT/base_stack/pgadmin/.pgpass"
    touch "$PROJECT_ROOT/base_stack/pgadmin/.servers.json"
    chmod 600 "$PROJECT_ROOT/base_stack/pgadmin/.pgpass"

    # Create main Docker stack files
    touch "$PROJECT_ROOT/base_stack/docker-compose.yml"
    touch "$PROJECT_ROOT/base_stack/Caddyfile"
    touch "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}_requirements.txt"

    echo "✅ Docker-related files and directories created successfully."
}

# write on docker-compose.yml file
write_docker_compose() {
echo "Writing docker-compose.yml..."
cat <<EOF > "$PROJECT_ROOT/base_stack/docker-compose.yml"
services:
  db:
    image: postgres:15
    container_name: postgres-container
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${db_user}
      POSTGRES_PASSWORD: ${db_pass}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - odoo-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${db_user}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

  # Container name must same as service name and conf file name
  ${comp_name}_odoo${odoo_version}:
    build:
      context: .
      dockerfile: ${comp_name}_odoo${odoo_version}.dockerfile
    container_name: ${comp_name}_odoo${odoo_version}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      - HOST=db
      - USER=${db_user}
      - PASSWORD=${db_pass}
    volumes:
      - ../custom-addons/odoo-${odoo_version}ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-${odoo_version}-ee
      - ./${comp_name}_odoo${odoo_version}.conf:/etc/odoo/${comp_name}_odoo${odoo_version}.conf
      - odoo_db_data:/var/lib/odoo
      - ../logs/odoo-logs:/var/log/odoo
    command: >
      odoo -d ${comp_name}-odoo${odoo_version}-db -i ${ODOO_MODULES} --config=/etc/odoo/${comp_name}_odoo${odoo_version}.conf
    networks:
      - odoo-net


  pgadmin:
    image: dpage/pgadmin4:9
    container_name: pgadmin4
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      PGADMIN_DEFAULT_EMAIL: ${pg_user}
      PGADMIN_DEFAULT_PASSWORD: ${pg_pass}
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./pgadmin/.servers.json:/pgadmin4/servers.json
      - ./pgadmin/.pgpass:/pgpass
    networks:
      - odoo-net

  caddy:
    image: caddy:latest
    container_name: caddy-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ../logs/caddy-logs:/caddy-logs
      - ../caddy-sites:/etc/caddy/sites
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - ${comp_name}_odoo${odoo_version}
      - pgadmin
    networks:
      - odoo-net

networks:
  odoo-net:
    name: odoo-net
    driver: bridge

volumes:
  postgres_data:
  odoo_db_data:
  pgadmin_data:
  caddy_data:
  caddy_config:

EOF
echo "✅ docker-compose.yml written successfully."
}


# write on pgadmin/.pgpass file
write_pgpass() {
echo "Writing pgadmin/.pgpass..."
cat <<EOF > "$PROJECT_ROOT/base_stack/pgadmin/.pgpass"
# Format: hostname:port:database:username:password
db:5432:*:${db_user}:${db_pass}
EOF
echo "✅ base_stack/pgadmin/.pgpass written successfully."
}


# write on pgadmin/.servers.json file
write_servers_json() {
echo "Writing base_stack/pgadmin/.servers.json..."
cat <<EOF > "$PROJECT_ROOT/base_stack/pgadmin/.servers.json"
{
    "Servers": {
        "1": {
            "Name": "PostgreSQL Server",
            "Group": "Odoo Databases",
            "Host": "db",
            "Port": 5432,
            "MaintenanceDB": "postgres",
            "Username": "${db_user}",
            "SSLMode": "prefer",
            "PassFile": "/pgpass"
        }
    }
}
EOF
echo "✅ pgadmin/.servers.json written successfully."
}


# write on .conf file
write_odoo_conf() {
echo "Writing base_stack/${comp_name}_odoo${odoo_version}.conf..."
cat <<EOF > "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}.conf"
[options]
admin_passwd = ${odoo_conf_admin_pass}
db_user = ${db_user}
db_password = ${db_pass}
db_host = db
db_port = 5432
addons_path = /mnt/odoo-${odoo_version}-ee,/mnt/extra-addons
db_filter = ^${comp_name}_odoo${odoo_version}_db$
proxy_mode = True
logfile = /var/log/odoo/${comp_name}_odoo${odoo_version}.log
without_demo = ${demo_data}
EOF
echo "✅ base_stack/${comp_name}_odoo${odoo_version}.conf written successfully."
}


# write on docker file
write_dockerfile() {
echo "Writing base_stack/${comp_name}_odoo${odoo_version}.dockerfile..."
cat <<EOF > "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}.dockerfile"
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
echo "✅ base_stack/${comp_name}_odoo${odoo_version}.dockerfile written successfully."
}

# write on Caddyfile

write_caddyfile() {
echo "Writing Caddyfile..."
cat <<EOF > "$PROJECT_ROOT/base_stack/Caddyfile"
{
    email ${pg_user}
}
import /etc/caddy/sites/*
EOF
echo "✅ Caddyfile written successfully."
}

write_caddy_site_file() {
echo "Writing caddy-site file..."
cat <<EOF > "$PROJECT_ROOT/caddy-sites/base_stack_${comp_name}_odoo${odoo_version}.caddy"
${domain} {
    reverse_proxy ${comp_name}_odoo${odoo_version}:8069
    log {
        output file /caddy-logs/${comp_name}_odoo${odoo_version}_access.log
    }
}
EOF
echo "✅ Caddy site file written successfully."
}

# write on requirements file
write_requirements() {
echo "Writing base_stack/${comp_name}_odoo${odoo_version}_requirements.txt..."
cat <<EOF > "$PROJECT_ROOT/base_stack/${comp_name}_odoo${odoo_version}_requirements.txt"
pydantic==2.10.6
pydantic-core==2.27.2
email_validator==2.2.0
phonenumbers==9.0.12
EOF
echo "✅ base_stack/${comp_name}_odoo${odoo_version}_requirements.txt written successfully."
}


# Call the functions
gather_inputs
create_custom_addons_directories
extract_theme_for_community
create_directory_and_files
write_requirements
write_docker_compose
write_dockerfile
write_pgpass
write_servers_json
write_odoo_conf
write_caddyfile
write_caddy_site_file

