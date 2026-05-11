## 🚀 start_base_stack.sh

### 📌 Overview
start_base_stack.sh is the main entry point for initializing the Odoo environment.  
It prepares Docker, builds base images, generates configuration, and starts core services.

This script must be executed before creating any template or test stacks.

---

### 🎯 Purpose
- Setup a clean and consistent base environment  
- Build reusable Odoo Docker images  
- Create base stack configuration  
- Start core services (Odoo, PostgreSQL, Caddy, pgAdmin)  

👉 The base stack is the foundation for all template and test instances

---

### ⚙️ Workflow

1. Load Configuration  
   - Reads configs/.base_stack.conf  
   - Uses COMPANY_NAME and ODOO_VERSION  

2. Prepare Docker Environment  
   - Calls: scripts/prepare_docker.sh  
   - Installs dependencies and ensures Docker is ready  

3. Build Base Images  
   - Calls: scripts/build_odoo_base_images.sh  
   - Builds:
     - odoo:<version>
     - odoo-custom:<version>  

4. Setup Base Stack  
   - Calls: scripts/setup_base_stack.sh  
   - Creates base_stack directory with:
     - docker-compose.yml  
     - Odoo config (.conf)  
     - Dockerfile  
     - requirements.txt  
     - Caddy config  
     - pgAdmin files  

   - If base_stack exists:
     - user chooses overwrite or reuse  

5. Verify Required Files  
   Ensures all required files exist before starting:
   - docker-compose.yml  
   - Caddyfile  
   - Odoo config  
   - Dockerfile  
   - requirements.txt  
   - pgAdmin configs  

6. Start Base Stack  
   - Runs docker compose up -d or restart  
   - Starts:
     - Odoo  
     - PostgreSQL  
     - Caddy  
     - pgAdmin  

---

### 🌐 Output
After successful execution:

https://${DOMAIN}/odoo

---

### 🧠 Architecture Concept
Base Stack → Core Infrastructure  
Template Stacks → Prebuilt reusable instances  
Test Stacks → Runtime instances  

---

### ⚠️ Notes
- configs/.base_stack.conf must exist  
- May overwrite base_stack directory  
- Docker images are built once and reused  

---

### ✅ Summary
Initialize → Build → Configure → Verify → Run