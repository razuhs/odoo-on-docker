#!/bin/bash

# update_all.sh
#
# Purpose:
#   Prepare and refresh local Odoo server repositories, update database
#   expiration settings, recreate and restart stack directories.
#
# Scheduler:
#   Defined in: /etc/cron.d/update_odoo
#   Schedule:   0 19 * * * (daily at 19:00 UTC / 01:00 AM BDT)
#   Run as:     bjit
#   To edit:    sudo nano /etc/cron.d/update_odoo
#
# Execution order:
#   1) clone_odoo_servers
#   2) update_odoo_servers
#   3) update_database_expiration.sh
#   4) restart_stack_directories
#
# Stack restart selection:
#   - Includes: directories under the parent folder ending with "_stack"
#   - Excludes: directory names starting with "base" or "template"
#
# Prerequisites:
#   - Git access to Community and Enterprise repositories
#   - Docker and Docker Compose available for stack restart and DB operations
#   - Required scripts available in the same scripts directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p /opt/odoo/server

clone_odoo_servers() {
    # Clone missing Community and Enterprise repositories for versions 16 to 19.
    for version in 16 17 18 19; do
        if [ ! -d "/opt/odoo/server/odoo-${version}" ]; then
            echo "Cloning Odoo ${version}..."
            if ! git clone --single-branch --branch ${version}.0 https://github.com/odoo/odoo.git /opt/odoo/server/odoo-${version}; then
                echo "ERROR: Failed to clone Odoo ${version}" >&2
                exit 1
            fi
        else
            echo "Odoo ${version} already exists. Skipping clone."
        fi
    done

    for version in 16 17 18 19; do
        if [ ! -d "/opt/odoo/server/enterprise-${version}" ]; then
            echo "Cloning Enterprise ${version}..."
            if ! git clone --single-branch --branch ${version}.0 git@github.com:odoo/enterprise.git /opt/odoo/server/enterprise-${version}; then
                echo "ERROR: Failed to clone Enterprise ${version}. Check SSH key and access permissions." >&2
                exit 1
            fi
        else
            echo "Enterprise ${version} already exists. Skipping clone."
        fi
    done
}

update_odoo_servers() {
    # Update already cloned Community and Enterprise repositories for versions 16 to 19.
    for version in 16 17 18 19; do
        if [ -d "/opt/odoo/server/odoo-${version}" ]; then
            echo
            echo
            echo "Updating Odoo ${version}..."
            cd /opt/odoo/server/odoo-${version}
            if ! git pull; then
                echo "ERROR: Failed to update Odoo ${version}" >&2
                exit 1
            fi
            cd - > /dev/null
        else
            echo "Odoo ${version} not found. Skipping update."
        fi
    done

    for version in 16 17 18 19; do
        if [ -d "/opt/odoo/server/enterprise-${version}" ]; then
            echo
            echo
            echo "Updating Enterprise ${version}..."
            cd /opt/odoo/server/enterprise-${version}
            if ! git pull; then
                echo "ERROR: Failed to update Enterprise ${version}" >&2
                exit 1
            fi
            cd - > /dev/null
        else
            echo "Enterprise ${version} not found. Skipping update."
        fi
    done
}

restart_stack_directories() {
    local stack_directories=()
    local stack_path

    while IFS= read -r -d '' stack_path; do
        stack_directories+=("$(basename "$stack_path")")
    done < <(
        find "$PARENT_DIR" -mindepth 1 -maxdepth 1 -type d -name '*_stack' \
            ! -name 'base*' \
            ! -name 'template*' \
            -print0 | sort -z
    )

    if [ ${#stack_directories[@]} -eq 0 ]; then
        echo "No directories ending with _stack found in $PARENT_DIR"
        return
    fi

    echo "Stack directories: ${stack_directories[*]}"

    for directory_name in "${stack_directories[@]}"; do
        echo "Recreating stack ${directory_name}..."
        if ! (cd "$PARENT_DIR/$directory_name" && docker compose up -d --force-recreate); then
            echo "ERROR: Failed to recreate stack ${directory_name}" >&2
            exit 1
        fi

        echo "Restarting stack ${directory_name}..."
        if ! (cd "$SCRIPT_DIR" && ./restart_stack.sh "$directory_name"); then
            echo "ERROR: Failed to restart stack ${directory_name}" >&2
            exit 1
        fi

        
    done
}

clone_odoo_servers
update_odoo_servers
"$SCRIPT_DIR/update_database_expiration.sh"
restart_stack_directories



