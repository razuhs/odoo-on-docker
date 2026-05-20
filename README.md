# Odoo on Docker Setup Instructions

1. Navigate to scripts directory and run the prepare docker script:
   ```bash
   cd scripts
   ./prepare_docker.sh
   ```

2. Build odoo base images:
   ```bash
   ./build_odoo_base_images.sh
   ```

3. Start the base stack (make sure to edit `configs/.base_stack.conf` first):
   ```bash
   ./start_base_stack.sh
   ```

4. Start the template stack:
   ```bash
   ./start_template_stack.sh
   ```

5. Wait for Odoo to initialize databases for 16-19 CE & EE with default module installation (~4 hours).

6. Create template stack:
   ```bash
   ./make_template_stack.sh
   ```
   (This will take 30 minutes max)

7. Start test stack:
   ```bash
   ./start_test_stack.sh
   ```
   This will create and run 16 test instances for every 16 templates created earlier.

8. Once tested successfully, remove test stacks:
   ```bash
   ./remove_test_stacks.sh
   ```

9. Remove template stacks:
   ```bash
   ./remove_template_stacks.sh
   ```

10. Remove config files:
    ```bash
    ./remove_configs.sh
    ```
    This deletes the config files generated for creating templates and test stacks.
