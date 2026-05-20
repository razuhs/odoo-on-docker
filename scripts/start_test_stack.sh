#!/bin/bash

# Call and execute generate_test_configs.sh
./generate_test_configs.sh

# Get list of all files in configs that start with ".test"
test_files=$(cd ../configs && ls .test* 2>/dev/null && cd - > /dev/null)
echo test_files: $test_files

# Loop over the test files and call ./start_demo_stack with each file name
for file in $test_files; do
    echo "Starting stack for config: $file"
    ./start_demo_stack.sh "$file"
done