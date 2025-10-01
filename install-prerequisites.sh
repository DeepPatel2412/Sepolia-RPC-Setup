#!/bin/bash

set -e

# Temporarily mask motd-news reboot notifications
sudo systemctl mask motd-news.service motd-news.timer > /dev/null 2>&1 || true

if [ ! -f /etc/os-release ]; then
  echo "Not Ubuntu or Debian"
  # Unmask motd-news before exiting
  sudo systemctl unmask motd-news.service motd-news.timer > /dev/null 2>&1 || true
  exit 1
fi

echo "🔄 Updating package lists..."
sudo apt-get update -y > /dev/null 2>&1

echo "📦 Installing prerequisite packages..."
sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ufw screen gawk > /dev/null 2>&1

echo "🧹 Removing old or conflicting Docker packages..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; do
  sudo apt-get remove --purge -y $pkg > /dev/null 2>&1 || true
done

sudo apt-get autoremove -y > /dev/null 2>&1
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg

echo "🔄 Updating package lists before Docker repo setup..."
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1

. /etc/os-release
repo_url="https://download.docker.com/linux/$ID"

echo "🔑 Adding Docker's official GPG key..."
curl -fsSL "$repo_url/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "📚 Adding Docker's official APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🔄 Updating package lists with Docker repo..."
sudo apt-get update -y > /dev/null 2>&1

echo "🐳 Installing Docker components..."
sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

echo "🚦 Enabling and starting Docker service..."
sudo systemctl enable docker > /dev/null 2>&1
sudo systemctl restart docker > /dev/null 2>&1

echo "✅ Testing Docker installation..."
if sudo docker run hello-world > /dev/null 2>&1; then
  sudo docker rm $(sudo docker ps -a --filter "ancestor=hello-world" --format "{{.ID}}") --force > /dev/null 2>&1 || true
  sudo docker image rm hello-world > /dev/null 2>&1 || true
  clear
  echo -e "\u2022 Docker Installed \u2714"
else
  echo "Docker installation test failed."
  # Unmask motd-news before exiting
  sudo systemctl unmask motd-news.service motd-news.timer > /dev/null 2>&1 || true
  exit 1
fi

# Unmask motd-news reboot notifications to restore original state
sudo systemctl unmask motd-news.service motd-news.timer > /dev/null 2>&1 || true
