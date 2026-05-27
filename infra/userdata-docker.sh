#!/bin/bash
# cloud-init / userdata script for Ubuntu 22.04 to install Docker and prepare deploy user
set -euo pipefail

# Update and install prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Install Docker
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
rm /tmp/get-docker.sh

# Install docker compose plugin
apt-get install -y docker-compose-plugin

# Create deploy user and setup ssh directory (will copy authorized_keys later)
if ! id -u deploy >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" deploy
fi
mkdir -p /home/deploy/.ssh
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# Allow deploy user to run docker without sudo
usermod -aG docker deploy

# Create project dir
mkdir -p /opt/proyecto
chown -R deploy:deploy /opt/proyecto

# Enable docker service
systemctl enable docker.service
systemctl start docker.service

# Healthcheck script placeholder
cat > /usr/local/bin/container-healthcheck.sh <<'HC'
#!/bin/bash
# simple healthcheck for docker
curl -sSf http://localhost:8080/actuator/health >/dev/null 2>&1 && exit 0 || exit 1
HC
chmod +x /usr/local/bin/container-healthcheck.sh

# Finished
echo "user-data script completed" > /var/log/user-data-complete
