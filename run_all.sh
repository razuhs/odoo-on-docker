#!/bin/bash
set -e

echo "Starting Odoo Docker setup..."

echo "Step 1: Preparing Docker environment..."
./prepare_docker.sh

echo "Step 2: Setting up Odoo Docker stack..."
./setup_odoo_docker_stack.sh


echo "All steps completed successfully!"