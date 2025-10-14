#!/bin/bash
set -e

script_failed=0
install_timeout=600  # 10 minutes timeout

# Ensure running on Debian or Ubuntu
if [ ! -f /etc/os-release ]; then
  echo "Error: Not Ubuntu or Debian"
  script_failed=1
else
  . /etc/os-release
  if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
    echo "Error: This script only supports Debian or Ubuntu."
    script_failed=1
  fi
fi

cleanup_partial_install() {
  echo "🧹 Cleaning previous Docker install attempts..."
  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose podman-docker containerd runc > /dev/null 2>&1 || true
  sudo apt-get autoremove -y > /dev/null 2>&1 || true
  sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
}

if [ $script_failed -eq 0 ]; then
  echo "🔄 Updating package lists..."
  DEBIAN_FRONTEND=noninteractive sudo apt-get update -y > /dev/null 2>&1 || script_failed=1
fi

# Main Docker Installation with timeout, silence output
if [ $script_failed -eq 0 ]; then
  echo "🐳 Installing Docker components (timeout ${install_timeout}s)..."
  if ! timeout $install_timeout bash -c '
      DEBIAN_FRONTEND=noninteractive sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release > /dev/null 2>&1 &&
      sudo install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1 &&
      curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1 &&
      sudo chmod a+r /etc/apt/keyrings/docker.gpg > /dev/null 2>&1 &&
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null &&
      DEBIAN_FRONTEND=noninteractive sudo apt-get update -y > /dev/null 2>&1 &&
      DEBIAN_FRONTEND=noninteractive sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    ' ; then
    echo "⚠️ Docker installation timed out or failed."
    script_failed=1
  fi
fi

if [ $script_failed -eq 0 ]; then
  echo "🚦 Enabling and starting Docker service..."
  sudo systemctl enable docker > /dev/null 2>&1 || true
  sudo systemctl restart docker > /dev/null 2>&1 || true
fi

if [ $script_failed -eq 0 ]; then
  echo "✅ Testing Docker installation..."
  if sudo docker run hello-world > /dev/null 2>&1; then
    sudo docker rm $(sudo docker ps -a --filter "ancestor=hello-world" --format "{{.ID}}") --force > /dev/null 2>&1 || true
    sudo docker image rm hello-world > /dev/null 2>&1 || true
    echo -e "\u2022 Docker Installed \u2714"
    exit 0
  else
    echo "⚠️ Docker test failed."
    script_failed=1
  fi
fi

# Fallback installation if main method failed or timed out
if [ $script_failed -ne 0 ]; then
  echo "🛠️ Running fallback Docker installation method..."
  cleanup_partial_install
  DEBIAN_FRONTEND=noninteractive curl -fsSL https://get.docker.com | sudo sh > /dev/null 2>&1
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Fallback Docker installation failed."
    exit 1
  fi
  echo "✅ Fallback Docker installation succeeded."
fi
