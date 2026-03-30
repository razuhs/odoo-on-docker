# ==========================================================
# 📘 TEMPLATE CREATION WORKFLOW
# ==========================================================
#
# 🚀 Step 1: Generate Template Config (if not already done)
# --------------------------------------------------------
# ./generate_template_configs.sh
#
#
# 🚀 Step 2: Start Template Stack
# --------------------------------------------------------
# ./start_demo_stack.sh .template19eewdd_stack.conf
#
# Example Output:
#   - Stack directory created
#   - docker-compose.yml generated
#   - Container started
#   - Volume created
#   - Caddy restarted
#
#
# 🌐 Step 3: Verify Instance Accessibility (IMPORTANT)
# ----------------------------------------------------
# Open in browser:
#
#   https://template19eewdd.app-odoo.bjitgroup.org/odoo
#
# Ensure:
#   ✔ Odoo UI loads successfully
#   ✔ No startup errors
#   ✔ Modules are installed
#
# ⚠️ Do NOT proceed if instance is not accessible
#
#
# 🧠 Step 4: Convert DB to Template
# --------------------------------------------------------
# ./make_template_db.sh template19eewdd_stack
# template19eewdd_stack -> stack directory name
# What happens:
#   - Waits for DB readiness
#   - Terminates active DB connections
#   - Marks DB as template (datistemplate = true)
#   - Sets connection limit = 0 (locks DB)
#   - Stops Odoo container
#
#
# 📦 Final Output:
# --------------------------------------------------------
# ✔ Template Database:
#     template19eewdd-odoo19-db
#
# ✔ Filestore Volume:
#     template19eewdd_stack_odoo_db_data
#
# ✔ Container:
#     Stopped (template is not meant to run)
#
#
# 🧠 Template Characteristics:
# --------------------------------------------------------
# - is_template = true
# - conn_limit = 0 (no connections allowed)
# - Used ONLY for cloning new instances
# - Should NOT be modified or used directly
#
#
# 🔁 Step 5: Use Template for New Instances
# --------------------------------------------------------
# Use TEMPLATE=False in config to:
#   - Clone DB from template
#   - Copy filestore
#   - Create new instance quickly
#
#
# ⚠️ Important Notes:
# --------------------------------------------------------
# - Always verify URL before making template
# - Template stack should remain STOPPED after creation
# - Do NOT delete template DB or volume unless rebuilding
#
#
# 💡 Tip:
# --------------------------------------------------------
# To verify template DB:
#
#   ./list_databases.sh
#
# Expected:
#   template19eewdd-odoo19-db → is_template = YES
#
#
# ==========================================================