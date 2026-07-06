#!/bin/bash

# Find directories in project root that start with "test"
test_dirs=($(find .. -maxdepth 1 -type d -name "test*" -printf '%f\n' 2>/dev/null))

# Check if test_dirs is empty
if [ ${#test_dirs[@]} -eq 0 ]; then
    echo "❌ No test directories found to remove."
    exit 0
fi

# Loop over the list and call remove_stack for each
echo "🚀 Removing test stacks..."

echo test_dirs: ${test_dirs[*]}
for dir in "${test_dirs[@]}"; do
    bash "$(dirname "$0")/remove_stack.sh" "$dir" --with-db
done
