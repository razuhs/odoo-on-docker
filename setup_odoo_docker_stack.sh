#!/bin/bash
set -euo pipefail

custom_addons_dir="$(pwd)/custom-addons"

ensure_dependencies() {
    # Ensure git exists
    if ! command -v git >/dev/null 2>&1; then
        echo "❌ git is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y git
        echo "✅ git installed successfully."
    else
        echo "✅ git is already installed."
    fi

    # Ensure unzip is installed
    if ! command -v unzip >/dev/null 2>&1; then
        echo "❌ unzip is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y unzip
        echo "✅ unzip installed successfully."
    else
        echo "✅ unzip is already installed."
    fi

    # Check if Docker Engine is installed
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker Engine is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y docker.io
        echo "✅ Docker Engine installed successfully."
    else
        echo "✅ Docker Engine is already installed."
    fi

    # Check if Docker Compose plugin is installed
    if ! docker compose version >/dev/null 2>&1; then
        echo "❌ Docker Compose plugin is required but not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
        echo "✅ Docker Compose plugin installed successfully."
    else
        echo "✅ Docker Compose plugin is already installed."
    fi

    # Check if inotify-tools is installed
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "❌ inotify-tools is required but not installed. Installing..."
        sudo apt update
        sudo apt install -y inotify-tools
        echo "✅ inotify-tools installed successfully."
    else
        echo "✅ inotify-tools is already installed."
    fi
}

# Function to gather user inputs
gather_inputs() {
  # Detect latest Odoo version
  LATEST=$(
    git ls-remote --heads https://github.com/odoo/odoo.git \
    | grep -E 'refs/heads/[0-9]+\.[0-9]+$' \
    | sed 's#.*/##' \
    | sort -V \
    | tail -1 \
    | cut -d'.' -f1
  ).
  START=16
  LATEST=${LATEST%%.*}
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
  echo -n "Enter company name (spaces will be converted to _): "
  read -r comp_name
  # Convert spaces to underscores
  comp_name="${comp_name// /_}"

  # Optional: convert to lowercase
  comp_name="${comp_name,,}"

  echo "Company name set to: $comp_name"

  # Domain Name
  echo -n "Enter a valid domain name (e.g. example.com):"
  read -r domain

  echo "Domain set to: $domain"

  # Enterprise Addons Path
  read -r -p "Enter Odoo ${base_version}.0 enterprise addons parent path (e.g. /opt/odoo/enterprise/${base_version}.0): " ent_path
  # Validate path exists
  if [ ! -d "$ent_path" ]; then
      echo "❌ Directory does not exist: $ent_path"
      exit 1
  fi

  echo "Enterprise addons path set to: $ent_path"

  while true; do
    read -p "Enter DB username (default: YourCompanyUser): " db_user
    db_user=${db_user:-YourCompanyUser}

    # Reject root user
    if [[ "$db_user" == "root" ]]; then
        echo "❌ 'root' cannot be used as DB username. Please choose another name."
        continue
    fi

    # Check if user exists
    if id "$db_user" >/dev/null 2>&1; then
        echo "✅ User '$db_user' already exists."
    else
        echo "⚠️ User '$db_user' does not exist. Creating it..."
        sudo useradd -m -s /bin/bash "$db_user"
        echo "✅ User '$db_user' created successfully."
    fi

    break
  done

  read -s -p "Enter DB password (default: YourCompanyPass): " db_pass
  db_pass=${db_pass:-YourCompanyPass}
  echo

  while true; do
    read -p "Enter PG ADMIN email (default: admin@company.com): " pg_user
    pg_user=${pg_user:-admin@company.com}

    # email validation regex
    if [[ "$pg_user" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        break
    else
        echo "❌ Invalid email format. Please enter a valid email like user@example.com"
    fi
  done

  read -s -p "Enter PG ADMIN password (default: YourCompanyPass): " pg_pass
  pg_pass=${pg_pass:-YourCompanyPass}
  echo

  read -s -p "Enter Odoo Config ADMIN password (default: YourCompanyPass): " odoo_conf_admin_pass
  odoo_conf_admin_pass=${odoo_conf_admin_pass:-YourCompanyPass}

  echo

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

    echo "📦 Copying Extracted Theme Module For All Community Version. e.g. 16,17, ... $v"
    unzip -q "$INNER_ZIP" -d "$TARGET_DIR"
    echo "✅ Copied into $TARGET_DIR"
done

# Cleanup.
echo "Cleaning Up Extracted Theme Module ..."
rm -rf muk_tmp
}


# create docker related files and directories
create_directory_and_files() {
echo "Creating Docker-related files and directories..."
sudo rm -rf conf dockerfile pgadmin Caddyfile docker-compose.yml caddy-logs odoo-container-logs requirements
# Create `conf` directory and `comp_name.conf` file
mkdir -p conf && touch "conf/${comp_name}_odoo${base_version}.conf"

# create caddy-logs directory
mkdir -p caddy-logs
sudo chown -R root:root caddy-logs
sudo chmod -R 755 caddy-logs

# create odoo-container-logs directory
mkdir -p odoo-container-logs
sudo chown -R root:root odoo-container-logs
sudo chmod -R 755 odoo-container-logs

# create requirements directory
mkdir -p requirements

# Create `pgadmin` directory and `.pgpass` file
mkdir -p pgadmin && touch "pgadmin/.pgpass" "pgadmin/.servers.json"

# Create `dockerfile` directory and `.$base_version.dockerfile` file
mkdir -p dockerfile && touch "dockerfile/${comp_name}_odoo${base_version}.dockerfile"

touch docker-compose.yml Caddyfile
}

# write on docker-compose.yml file
write_docker_compose() {
cat <<EOF > docker-compose.yml
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

  # Container name must same as service name and conf file name
  ${comp_name}_odoo${base_version}:
    ports:
      - "8069:8069"
    build:
      context: .
      dockerfile: dockerfile/${comp_name}_odoo${base_version}.dockerfile
    container_name: ${comp_name}_odoo${base_version}
    restart: unless-stopped
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=${db_user}
      - PASSWORD=${db_pass}
    volumes:
      - /opt/odoo/custom-addons/odoo-${base_version}ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-${base_version}-ee
      - ./conf/${comp_name}_odoo${base_version}.conf:/etc/odoo/${comp_name}_odoo${base_version}.conf
      - odoo_db_data:/var/lib/odoo
      - ./odoo-container-logs:/var/log/odoo
    command: >
      odoo -d ${comp_name}-odoo${base_version}-db -i website --config=/etc/odoo/${comp_name}_odoo${base_version}.conf
    networks:
      - odoo-net


  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: pgadmin4
    restart: unless-stopped
    depends_on:
      - db
    environment:
      PGADMIN_DEFAULT_EMAIL: ${pg_user}
      PGADMIN_DEFAULT_PASSWORD: ${pg_pass}
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./pgadmin/servers.json:/pgadmin4/servers.json
      - ./pgadmin/pgpass:/pgpass
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
      - ./caddy-logs:/caddy-logs
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
}


# write on pgadmin/.pgpass file
write_pgpass() {
cat <<EOF > pgadmin/.pgpass
# Format: hostname:port:database:username:password
db:5432:*:${db_user}:${db_pass}
EOF
}


# write on pgadmin/.servers.json file
write_servers_json() {
cat <<EOF > pgadmin/.servers.json
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
}


# write on .conf file
write_odoo_conf() {
cat <<EOF > conf/"${comp_name}"_odoo"${base_version}".conf
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
}


# write on docker file
write_dockerfile() {
cat <<EOF > dockerfile/${comp_name}_odoo${base_version}.dockerfile
FROM odoo-custom:${base_version}

USER root

COPY requirements/${comp_name}_odoo${base_version}_requirements.txt /tmp/req.txt

RUN if [ "${base_version}" -ge 18 ]; then
    pip install --break-system-packages -r /tmp/req.txt
else
    pip install -r /tmp/req.txt
fi

USER odoo
EOF
}

# write on Caddyfile
write_caddyfile() {
cat <<EOF > Caddyfile
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
}

# write on requirements file
write_requirements() {
mkdir -p requirements
cat <<EOF > requirements/"${comp_name}"_odoo"${base_version}"_requirements.txt
pydantic==2.10.6
pydantic-core==2.27.2
email_validator==2.2.0
phonenumbers==9.0.12
EOF
}
# Call the functions

ensure_dependencies
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


