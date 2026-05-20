#!/bin/bash

# Find all directories in project root that start with "template"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIRS=()

while IFS= read -r dir; do
    TEMPLATE_DIRS+=("$(basename "$dir")")
done < <(find "$PROJECT_ROOT" -maxdepth 1 -type d -name "template*")

# Loop over the list and call make_template_db.sh for each
for template_name in "${TEMPLATE_DIRS[@]}"; do
    bash "$PROJECT_ROOT/scripts/make_template_db.sh" "$template_name"
done 