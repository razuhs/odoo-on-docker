# odoo-on-docker

Automate Odoo server creation and management using Docker.

---

## Clean Docker Environment (Fresh Start)

Before deploying a new stack, you may want to completely clean the Docker environment.
⚠️ **Warning:** The following steps will remove all containers, images, volumes, and networks.

---

### 1️⃣ Stop and Remove All Containers

Stop all running containers:

```bash
docker stop $(docker ps -aq)
```

Remove all containers:

```bash
docker rm $(docker ps -aq)
```

---

### 2️⃣ Remove All Docker Images

Remove every Docker image from the system:

```bash
docker rmi -f $(docker images -aq)
```

---

### 3️⃣ Remove Docker Volumes

Remove all Docker volumes:

```bash
docker volume rm $(docker volume ls -q)
```

If some volumes are still in use or cannot be removed, run:

```bash
docker volume prune -f
```

---

### 4️⃣ Remove Docker Networks (Optional)

Clean unused Docker networks:

```bash
docker network prune -f
```

---

### 5️⃣ One-Command Cleanup (Recommended)

Docker provides a single command to remove unused containers, images, networks, volumes, and build cache:

```bash
docker system prune -a --volumes -f
```

This is the easiest way to reset your Docker environment.

---

## Result

After running these commands, your Docker environment will be completely clean and ready for a fresh Odoo deployment.
