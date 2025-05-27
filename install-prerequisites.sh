#!/bin/bash

set -e

echo "🔄 [1/7] Updating and upgrading all system packages..."
sudo apt update -y && sudo apt upgrade -y

echo "🧹 [2/7] Removing old or conflicting Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

echo "📦 [3/7] Installing dependencies for Docker repository..."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

echo "🔑 [4/7] Adding Docker’s official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "📚 [5/7] Adding Docker’s official repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🔄 [6/7] Updating and upgrading all system packages again (with Docker repo)..."
sudo apt update -y && sudo apt upgrade -y

echo "🐳 [7/7] Installing Docker Engine, CLI, containerd, Buildx, and Compose plugin..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "🚦 Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl restart docker

echo "✅ Testing Docker installation..."
sudo docker run hello-world

echo "🎉 Docker and Docker Compose are fully installed and up to date!"
