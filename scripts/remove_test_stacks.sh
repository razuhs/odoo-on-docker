#!/bin/bash

# Find directories in project root that start with "test"
test_dirs=($(find .. -maxdepth 1 -type d -name "test*" -printf '%f\n' 2>/dev/null))

# Loop over the list and call remove_stack for each
echo "🚀 Removing test stacks..."

echo test_dirs: ${test_dirs[*]}
for dir in "${test_dirs[@]}"; do
    bash "$(dirname "$0")/remove_stack.sh" "$dir" --with-db
done
