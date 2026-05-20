#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/configs"

# Check if configs directory exists
if [ ! -d "$CONFIGS_DIR" ]; then
    echo "Error: configs directory not found at $CONFIGS_DIR"
    exit 1
fi

# Execute generate_template_configs.sh
"$SCRIPT_DIR/generate_template_configs.sh"

# List all filenames in configs directory that start with .template
templates=($(ls -1 "$CONFIGS_DIR"/.template* 2>/dev/null | xargs -I {} basename {}))

# Check if any templates were found
if [ ${#templates[@]} -eq 0 ]; then
    echo "No template files found in configs directory"
    exit 1
fi

# Loop over each template
for template in "${templates[@]}"; do
    echo "$template"
    "$SCRIPT_DIR/start_demo_stack.sh" "$template"
done
