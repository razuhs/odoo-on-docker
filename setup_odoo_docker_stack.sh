#!/bin/bash
set -euo pipefail

custom_addons_dir="$(pwd)/custom-addons"

# Function to gather user inputs
gather_inputs() {

  CONFIG_FILE=".odoo_stack.conf"

  if [ ! -f "$CONFIG_FILE" ]; then
      echo "❌ Config file $CONFIG_FILE not found."
      exit 1
  fi

  source "$CONFIG_FILE"

  START=16
  LATEST=19

  base_version="${BASE_VERSION:-$LATEST}"

  # Validate numeric
  if ! [[ "$base_version" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid BASE_VERSION."
      exit 1
  fi

  if (( base_version < START || base_version > LATEST )); then
      echo "❌ Version must be between $START and $LATEST"
      exit 1
  fi

  comp_name="${COMPANY_NAME// /_}"
  comp_name="${comp_name,,}"

  domain="$DOMAIN"

  VAR_NAME="ENTERPRISE_PATH_${base_version}"
  ent_path=$(eval echo \$$VAR_NAME)

  if [ -z "$ent_path" ]; then
      echo "❌ Enterprise path for Odoo $base_version not found."
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
  echo "Base/controller version : $base_version"
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
    # Create parent directory for custom-addons
    if [ -d "$custom_addons_dir" ]; then
        rm -rf "$custom_addons_dir"
    fi
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
extreact_theme_for_community() {
echo "📦 Extracting muk_web_theme.zip..."
unzip -q muk_web_theme.zip -d muk_tmp

for ((v=START; v<=LATEST; v++)); do
    TARGET_DIR="$custom_addons_dir/odoo-${v}ce-custom-addons"

    # Find correct version zip
    INNER_ZIP=$(find muk_tmp -type f -name "muk_web_theme-${v}.0.*.zip" | head -n 1)

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
rm -rf muk_tmp
}

# Create Docker-related files and directories
create_directory_and_files() {

    echo "Creating Docker-related files and directories..."

    # Remove existing directories to start fresh
    sudo rm -rf base_stack logs

    # Create main project and log directories
    mkdir -p base_stack
    mkdir -p logs/odoo-logs logs/caddy-logs

    # Set ownership for project files (host user)
    sudo chown -R 1000:1000 base_stack
    sudo chmod -R 775 base_stack

    # Set permissions for Odoo logs (Odoo container UID 101)
    sudo chown -R 101:101 logs/odoo-logs
    sudo chmod -R 775 logs/odoo-logs

    # Set permissions for Caddy logs (host user UID 1000)
    sudo chown -R 1000:1000 logs/caddy-logs
    sudo chmod -R 775 logs/caddy-logs

    # Create Odoo configuration file
    touch "base_stack/${comp_name}_odoo${base_version}.conf"

    # Create Dockerfile for the specific Odoo version
    touch "base_stack/${comp_name}_odoo${base_version}.dockerfile"

    # Create pgAdmin directory and required configuration files
    mkdir -p base_stack/pgadmin
    touch base_stack/pgadmin/.pgpass
    touch base_stack/pgadmin/.servers.json
    chmod 600 base_stack/pgadmin/.pgpass

    # Create main Docker stack files
    touch base_stack/docker-compose.yml
    touch base_stack/Caddyfile
    touch "base_stack/${comp_name}_odoo${base_version}_requirements.txt"

    echo "✅ Docker-related files and directories created successfully."
}

# write on docker-compose.yml file
write_docker_compose() {
echo "Writing docker-compose.yml..."
cat <<EOF > base_stack/docker-compose.yml
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
  ${comp_name}_odoo${base_version}:
    build:
      context: .
      dockerfile: ${comp_name}_odoo${base_version}.dockerfile
    container_name: ${comp_name}_odoo${base_version}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      - HOST=db
      - USER=${db_user}
      - PASSWORD=${db_pass}
    volumes:
      - ../custom-addons/odoo-${base_version}ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-${base_version}-ee
      - ./${comp_name}_odoo${base_version}.conf:/etc/odoo/${comp_name}_odoo${base_version}.conf
      - odoo_db_data:/var/lib/odoo
      - ../logs/odoo-logs:/var/log/odoo
    command: >
      odoo -d ${comp_name}-odoo${base_version}-db -i website --config=/etc/odoo/${comp_name}_odoo${base_version}.conf
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
      - ..logs/caddy-logs:/caddy-logs
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - ${comp_name}_odoo${base_version}
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
cat <<EOF > base_stack/pgadmin/.pgpass
# Format: hostname:port:database:username:password
db:5432:*:${db_user}:${db_pass}
EOF
echo "✅ base_stack/pgadmin/.pgpass written successfully."
}


# write on pgadmin/.servers.json file
write_servers_json() {
echo "Writing base_stack/pgadmin/.servers.json..."
cat <<EOF > base_stack/pgadmin/.servers.json
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
echo "Writing base_stack/${comp_name}_odoo${base_version}.conf..."
cat <<EOF > base_stack/"${comp_name}"_odoo"${base_version}".conf
[options]
admin_passwd = ${odoo_conf_admin_pass}
db_user = ${db_user}
db_password = ${db_pass}
db_host = db
db_port = 5432
addons_path = /mnt/odoo-${base_version}-ee,/mnt/extra-addons
db_filter = ^${comp_name}_odoo${base_version}_db$
proxy_mode = True
logfile = /var/log/odoo/${comp_name}_odoo${base_version}.log
EOF
echo "✅ base_stack/${comp_name}_odoo${base_version}.conf written successfully."
}


# write on docker file
write_dockerfile() {
echo "Writing base_stack/${comp_name}_odoo${base_version}.dockerfile..."
cat <<EOF > base_stack/"${comp_name}"_odoo"${base_version}".dockerfile
FROM odoo-custom:${base_version}

USER root

COPY ${comp_name}_odoo${base_version}_requirements.txt /tmp/req.txt

RUN if [ ${base_version} -ge 18 ]; then \\
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \\
else \\
    pip install --ignore-installed -r /tmp/req.txt; \\
fi

USER odoo
EOF
echo "✅ base_stack/${comp_name}_odoo${base_version}.dockerfile written successfully."
}

# write on Caddyfile
write_caddyfile() {
echo "Writing Caddyfile..."
cat <<EOF > base_stack/Caddyfile
${domain} {
    reverse_proxy ${comp_name}_odoo${base_version}:8069
    encode gzip
    log {
        output file /caddy-logs/${comp_name}_odoo${base_version}_access.log {
            roll_size 50mb
            roll_keep 10
            roll_keep_for 720h
        }
    }
}
EOF
echo "✅ Caddyfile written successfully."
}

# write on requirements file
write_requirements() {
echo "Writing base_stack/${comp_name}_odoo${base_version}_requirements.txt..."
cat <<EOF > base_stack/"${comp_name}"_odoo"${base_version}"_requirements.txt
pydantic==2.10.6
pydantic-core==2.27.2
email_validator==2.2.0
phonenumbers==9.0.12
EOF
echo "✅ base_stack/${comp_name}_odoo${base_version}_requirements.txt written successfully."
}


# Call the functions
gather_inputs
create_custom_addons_directories
extreact_theme_for_community
create_directory_and_files
write_requirements
write_docker_compose
write_dockerfile
write_pgpass
write_servers_json
write_odoo_conf
write_caddyfile

