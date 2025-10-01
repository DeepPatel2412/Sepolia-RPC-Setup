#!/bin/bash

set -e

script_failed=0

# Check if running on Debian/Ubuntu
if [ ! -f /etc/os-release ]; then
  echo "Error: Not Ubuntu or Debian"
  script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  echo "🔄 Updating package lists..."
  sudo apt-get update -y > /dev/null 2>&1 || script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  echo "📦 Installing prerequisite packages..."
  sudo apt install -y curl iptables build-essential git wget liblz4-tool jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev ufw screen gawk python3-pip > /dev/null 2>&1 || script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  echo "🧹 Removing old or conflicting Docker packages..."
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc docker-ce docker-ce-cli; do
    sudo apt-get remove --purge -y $pkg > /dev/null 2>&1 || echo "Warning: Failed to remove $pkg, continuing."
  done
fi

if [ $script_failed -eq 0 ]; then
  sudo apt-get autoremove -y > /dev/null 2>&1 || true
  sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
fi

if [ $script_failed -eq 0 ]; then
  echo "🔄 Updating package lists before Docker repo setup..."
  sudo apt-get update -y > /dev/null 2>&1 || script_failed=1
  sudo apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null 2>&1 || script_failed=1
  sudo install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1 || script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  . /etc/os-release
  repo_url="https://download.docker.com/linux/$ID"

  echo "🔑 Adding Docker's official GPG key..."
  curl -fsSL "$repo_url/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1 || script_failed=1
  sudo chmod a+r /etc/apt/keyrings/docker.gpg > /dev/null 2>&1 || script_failed=1

  echo "📚 Adding Docker's official APT repository..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  echo "🔄 Updating package lists with Docker repo..."
  sudo apt-get update -y > /dev/null 2>&1 || script_failed=1
fi

if [ $script_failed -eq 0 ]; then
  echo "🐳 Installing Docker components..."
  sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" docker-ce docker-ce-cli containerd.io > /dev/null 2>&1 || { echo "Error: Docker engine install failed."; script_failed=1; }
fi

if [ $script_failed -eq 0 ]; then
  echo "📥 Installing Docker Compose v2 plugin manually..."
  mkdir -p ~/.docker/cli-plugins
  if curl -fsSL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose > /dev/null 2>&1; then
    chmod +x ~/.docker/cli-plugins/docker-compose
  else
    echo "Warning: Failed to download Docker Compose v2 plugin binary."
    script_failed=1
  fi
fi

if [ $script_failed -eq 0 ]; then
  echo "🚦 Enabling and starting Docker service..."
  sudo systemctl enable docker > /dev/null 2>&1 || { echo "Warning: Failed to enable Docker service."; }
  sudo systemctl restart docker > /dev/null 2>&1 || { echo "Warning: Failed to restart Docker service."; }
fi

if [ $script_failed -eq 0 ]; then
  echo "✅ Testing Docker installation..."
  if sudo docker run hello-world > /dev/null 2>&1; then
    sudo docker rm $(sudo docker ps -a --filter "ancestor=hello-world" --format "{{.ID}}") --force > /dev/null 2>&1 || true
    sudo docker image rm hello-world > /dev/null 2>&1 || true
    clear
    echo -e "\u2022 Docker Installed \u2714"
  else
    echo "Error: Docker installation test failed."
    script_failed=1
  fi
fi

if [ $script_failed -ne 0 ]; then
  echo "⚠️ Script finished with some warnings or errors. Please review the output for details."
fi
