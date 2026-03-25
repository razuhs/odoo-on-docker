# Odoo-on-Docker Hosting Platform

This project provides a lightweight **Odoo hosting platform** built with Docker.
It allows running **multiple Odoo instances in separate containers** while sharing common infrastructure such as PostgreSQL, Caddy (reverse proxy), and PgAdmin.

The goal of this project is to simplify **creating, managing, and monitoring multiple Odoo environments** on a single server.

---

# Platform Overview

The platform architecture separates **infrastructure services** from **Odoo instances**.

### Base Infrastructure (Base Stack)

The **base stack** provides shared services required by all Odoo instances:

* PostgreSQL database server
* Caddy reverse proxy (for routing domains to instances)
* PgAdmin (database management)
* Shared Docker network

This stack is created **once** and remains running.

---

### Odoo Instances

Each Odoo instance runs inside its **own container** and connects to the base infrastructure.

Example instances:

```
demo_odoo19
client1_odoo18
client2_odoo17
```

Each instance has its own:

* configuration file
* dockerfile
* requirements file
* domain routing
* logs

---

### Controller Module

One of the Odoo instances acts as the **controller module**.

This controller will:

* show how many Odoo instances are currently running
* allow users to request **new demo instances**
* manage instance lifecycle

This turns the project into a small **Odoo hosting platform**.

---

# Project Structure

```
odoo-on-docker/
│
├── base_stack/              # Base infrastructure stack
│   ├── docker-compose.yml
│   ├── Caddyfile
│   ├── pgadmin/
│   ├── *_odoo*.conf
│   ├── *_odoo*.dockerfile
│   └── *_requirements.txt
│
├── demo_stack/              # Example demo stack
│
├── caddy-sites/             # Domain routing configurations
│
├── configs/
│   ├── .base_stack.conf
│   └── .demo_stack.conf
│
├── scripts/                 # Automation scripts
│
├── custom-addons/
├── logs/
└── README.md
```

---

# Initial Setup

## 1. Clone the repository

```
git clone <repository-url>
cd odoo-on-docker
```

---

## 2. Navigate to scripts directory

All management scripts are located in the `scripts` directory.

```
cd scripts
```

---

# Preparing and Running the Base Stack

Before running any Odoo instances, we must prepare the **base stack**.

The base stack includes:

* PostgreSQL container
* PgAdmin container
* Caddy reverse proxy container
* Docker network for all stacks

---

## Run Base Stack Setup

Execute the following script:

```
./setup_base_stack.sh
```

This script will:

1. Load configuration from:

```
configs/.base_stack.conf
```

2. Generate required files:

* docker-compose.yml
* Odoo configuration file
* Dockerfile
* requirements.txt
* PgAdmin configuration
* Caddy configuration

3. Prepare required directories and volumes.

---

## Start the Base Stack

After setup completes, run:

```
./run_base_stack.sh
```

This will start:

```
postgres-container
pgadmin4
caddy-proxy
```

You can verify running containers using:

```
docker ps
```

---

# Managing Odoo Stacks

Each Odoo stack can be controlled using the scripts inside the `scripts` directory.

Example commands:

Start a stack:

```
./run_demo_stack.sh demo_stack
```

Stop a stack:

```
./stop_stack.sh demo_stack
```

Restart a stack:

```
./restart_stack.sh demo_stack
```

Install Python packages inside the Odoo container:

```
./install_package.sh demo_stack
```

---

# Domain Routing

Caddy automatically routes domains to the correct Odoo container.

Example configuration:

```
demo.app-odoo.example.com {
    reverse_proxy demo_odoo19:8069
}
```

Each stack adds its own configuration under:

```
caddy-sites/
```

After adding a new instance, Caddy is automatically reloaded.

---

# Logs

Logs are stored inside:

```
logs/
```

Each Odoo instance generates its own log file.

Example:

```
logs/demo_odoo19.log
```

---

# Requirements Files

Each stack contains a requirements file used to install Python dependencies inside the container.

Example:

```
demo_odoo19_requirements.txt
```

Packages can be installed automatically using:

```
./install_package.sh demo_stack
```

---

# Future Goals

Planned improvements for this platform:

* automatic demo instance creation
* self-service demo request portal
* monitoring dashboard
* automatic instance cleanup
* instance usage limits

---

# Summary

This project creates a **Docker-based Odoo hosting platform** capable of running multiple isolated Odoo environments on a single server while sharing infrastructure resources.

It is designed to be:

* modular
* scalable
* easy to automate
* easy to maintain
