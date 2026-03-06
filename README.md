# odoo-on-docker
Automate server creation and Management using docker

1️⃣ Stop and remove all containers

First stop everything:

docker stop $(docker ps -aq)

Remove them:

docker rm $(docker ps -aq)
2️⃣ Remove all images
docker rmi -f $(docker images -aq)

3️⃣ Remove volumes
docker volume rm $(docker volume ls -q)
docker volume prune -f

4️⃣ Remove networks (optional)
docker network prune -f
6️⃣ One-command cleanup (recommended)
docker system prune -a --volumes -f



