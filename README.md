🚀 Step 2: Build Template Stacks

From the scripts/ directory, run:

./build_all_template_stack.sh
🔹 What this does
Generates 16 template config files inside configs/
Covering:
Odoo versions: 16 → 19
Editions: CE & EE
Data modes: with demo (wdd) / without demo (wodd)
🔹 Stack Creation Process

For each generated config file:

The script calls:
./start_demo_stack.sh <config_file>
This script:
Prepares the stack environment

Calls:

./setup_demo_stack.sh
Creates:
Stack directory
Dockerfile
docker-compose.yml
Odoo config
Required supporting files
Then it:
Starts Docker containers
Initializes the Odoo database
🔹 Final Outcome
16 fully initialized Odoo stacks are created
Each stack has:
Running container
Initialized database
Ready-to-use environment
⚠️ Important Notes
The process runs sequentially (one stack at a time)
Each stack is validated to ensure the database is properly initialized
This step may take some time depending on system performance
🧠 Summary
generate configs → create stacks → start containers → initialize DBs