# ==========================================================
# 📘 CONFIG FILE FORMAT (.instancename_stack.conf)
# ==========================================================
#
# 📂 Location:
# -------------
# Config files must be placed inside:
#   configs/
#
# Naming convention:
#   .<instance_name>_stack.conf
#
# Example:
#   .template19eewdd_stack.conf
#
#
# 🧾 Example Config:
# ------------------
# DEMO_ODOO_VERSION=19
# DEMO_COMPANY_NAME=template19eewdd
# DEMO_DATA=False
# DEMO_ODOO_MODULES=base,web,mail,contacts,crm,sale_management,purchase_stock,stock,hr,project
# EDITION=EE
# TEMPLATE=True
#
#
# 🧠 Variable Explanation:
# ------------------------
#
# DEMO_ODOO_VERSION
#   → Odoo version to use
#   Example: 19
#
#
# DEMO_COMPANY_NAME
#   → Instance name (used for stack, DB, and logs)
#   Example: template19eewdd
#
#
# DEMO_DATA
#   → Controls demo data loading
#   ⚠️ NOTE (important behavior):
#     False → Load demo data
#     True  → Do NOT load demo data
#
#
# DEMO_ODOO_MODULES
#   → Comma-separated list of modules to install during DB creation
#
#   Example:
#     base,web,mail,contacts,crm,sale_management,purchase_stock,stock,hr,project
#
#
# EDITION
#   → Odoo edition
#     EE → Enterprise Edition
#     CE → Community Edition
#
#
# TEMPLATE
#   → Controls how database is created
#
#     True  → Create NEW database via Odoo initialization
#              (used for building template DB)
#
#     False → Create DB from an existing TEMPLATE database
#              (fast cloning)
#
#
# 🔁 Behavior Summary:
# --------------------
#
# TEMPLATE=True
#   → Fresh DB created by Odoo
#   → Modules installed
#   → Used to build template
#
# TEMPLATE=False
#   → DB cloned from prebuilt template
#   → Filestore copied
#   → Fast instance creation
#
#
# ⚠️ Important Notes:
# -------------------
# - TEMPLATE=True should be used ONLY for template stacks
# - TEMPLATE=False should be used for normal/demo instances
# - DEMO_DATA flag is intentionally inverted (False = load demo data)
#
#
# 🧠 Naming Impact:
# -----------------
# From DEMO_COMPANY_NAME, system derives:
#
#   Stack:   <name>_stack
#   DB:      <name>-odoo<version>-db
#   Volume:  <stack_name>_odoo_db_data
#   Logs:    logs/odoo-logs/<name>.log
#
#
# ==========================================================