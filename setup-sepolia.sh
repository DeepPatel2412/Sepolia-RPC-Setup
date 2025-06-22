#!/bin/bash

# --- Colors ---
NC='\033[0m'
ORANGE='\033[38;5;208m'
RED='\033[31m'
CYAN='\033[36m'
GREEN='\033[32m'

# --- Banner ---
echo -e "${ORANGE}============================================================${NC}"
echo -e "${ORANGE}      ETHEREUM SEPOLIA NODE INSTALLER (Reth)${NC}"
echo -e "${ORANGE}                by Creed${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- System Check ---
echo -e "${ORANGE}Recommended System Specifications:${NC}"
echo "• Storage: 750GB-1TB SSD"
echo "• CPU: 6+ cores"
echo "• RAM: 16GB+"
echo -e "${ORANGE}============================================================${NC}"
echo -e "${ORANGE}Checking your system resources...${NC}"

AVAILABLE_SPACE=$(df -BG --output=avail / | tail -1 | tr -d ' ')
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')

echo "Your System Resources:"
echo "• Available Storage: ${AVAILABLE_SPACE}B"
echo "• CPU Cores: ${CPU_CORES}"
echo "• Total RAM: ${TOTAL_RAM}GB"

WARNING=""
[[ ${AVAILABLE_SPACE%G} -lt 750 ]] && WARNING+="${RED}• Low storage space detected${NC}\n"
[[ ${CPU_CORES} -lt 6 ]] && WARNING+="${RED}• Insufficient CPU cores detected${NC}\n"
[[ ${TOTAL_RAM} -lt 16 ]] && WARNING+="${RED}• Insufficient RAM detected${NC}\n"

if [[ -n "$WARNING" ]]; then
  echo -e "${RED}Potential Issues Found:${NC}"
  printf "$WARNING"
  echo "What would you like to do?"
  echo -e "${CYAN}1: Continue installation despite warnings${NC}"
  echo -e "${CYAN}2: Abort installation${NC}"
  echo -n "• Enter your choice (1-2): "
  read CHOICE
  case "$CHOICE" in
    1)
      echo "Continuing installation..."
      ;;
    2)
      echo "Installation aborted by user."
      exit 1
      ;;
    *)
      echo "Invalid choice. Aborting installation."
      exit 1
      ;;
  esac
fi

echo -e "${ORANGE}============================================================${NC}"

# --- Prerequisites ---
echo -e "${ORANGE}Checking and installing prerequisites...${NC}"

# --- Docker & Compose ---
echo -e "${ORANGE}Checking for Docker and Docker Compose...${NC}"
if ! command -v docker >/dev/null 2>&1; then
  echo "• Docker not found. Installing prerequisites..."
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi

if ! sudo docker compose version >/dev/null 2>&1; then
  echo "• Docker Compose plugin not found. Installing prerequisites..."
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi
echo "• Docker and Compose are installed."

# --- aria2c ---
echo -e "${ORANGE}Checking for aria2c...${NC}"
if ! command -v aria2c >/dev/null 2>&1; then
  echo "• aria2c not found. Installing..."
  sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y aria2 >/dev/null 2>&1
  echo "• aria2c installed."
else
  echo "• aria2c already installed."
fi

# --- zstd ---
echo -e "${ORANGE}Checking for zstd...${NC}"
if ! command -v zstd >/dev/null 2>&1; then
  echo "• zstd not found. Installing..."
  sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y zstd >/dev/null 2>&1
  echo "• zstd installed."
else
  echo "• zstd already installed."
fi

# --- pv (optional, for progress bar) ---
echo -e "${ORANGE}Checking for pv (progress bar tool)...${NC}"
if ! command -v pv >/dev/null 2>&1; then
  echo -e "${CYAN}• pv not found. Installing it now...${NC}"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y pv >/dev/null 2>&1
    echo "• 'pv' installed for progress bar."
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y epel-release >/dev/null 2>&1 && sudo yum install -y pv >/dev/null 2>&1
    echo "• 'pv' installed for progress bar."
  else
    echo "• Could not install 'pv'. Progress bar will be limited."
  fi
else
  echo "• pv already installed."
fi

# --- Directory Structure ---
echo -e "${ORANGE}Creating directory structure...${NC}"
mkdir -p Ethereum/Execution Ethereum/Consensus
echo "• Directory structure ready."
echo -e "${ORANGE}============================================================${NC}"

# --- Fetch and Download Reth Snapshot ---
echo -e "${ORANGE}Fetching latest Reth snapshot for Sepolia...${NC}"
BLOCK_NUMBER=$(curl -s "https://snapshots.ethpandaops.io/sepolia/reth/latest")
if [ -z "$BLOCK_NUMBER" ]; then
  echo -e "${RED}ERROR: No Reth snapshot available for Sepolia. Please check the snapshot service.${NC}"
  exit 1
fi
echo "Latest Reth snapshot for Sepolia is at block: $BLOCK_NUMBER"

SNAPSHOT_URL="https://snapshots.ethpandaops.io/sepolia/reth/$BLOCK_NUMBER/snapshot.tar.zst"
echo "Snapshot URL: $SNAPSHOT_URL"

echo -e "${ORANGE}Downloading snapshot using aria2c (auto-resume enabled)...${NC}"
cd Ethereum/Execution
rm -rf ./*
aria2c -x16 -s16 --continue=true "$SNAPSHOT_URL" -o snapshot.tar.zst

if [ ! -f "snapshot.tar.zst" ]; then
  echo -e "${RED}ERROR: Download failed. Please check your network and try again.${NC}"
  cd ../..
  exit 1
fi

echo -e "${ORANGE}Extracting snapshot to Execution directory...${NC}"
tar -I zstd -xvf snapshot.tar.zst --strip-components=1
rm snapshot.tar.zst
cd ../..
echo -e "${GREEN}• Reth snapshot imported.${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- Generate JWT Secret ---
echo -e "${ORANGE}Generating JWT secret...${NC}"
if [ -f Ethereum/jwt.hex ]; then
  echo "• JWT secret already exists, skipping."
else
  openssl rand -hex 32 | tr -d "\n" > Ethereum/jwt.hex
  echo "• JWT secret created."
fi
echo -e "${ORANGE}============================================================${NC}"

# --- Write Docker Compose File ---
echo -e "${ORANGE}Writing Docker Compose file...${NC}"
cat > Ethereum/docker-compose.yml <<'EOF'
services:
  reth:
    image: ghcr.io/paradigmxyz/reth:latest
    container_name: reth
    restart: unless-stopped
    volumes:
      - ./Execution:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - node
      - --chain=sepolia
      - --full
      - --datadir=/data
      - --http
      - --http.addr=0.0.0.0
      - --http.api=eth,net,web3,admin
      - --http.corsdomain=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.api=eth,net,web3,admin
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.jwtsecret=/data/jwt.hex
    ports:
      - 8545:8545
      - 8546:8546

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:latest
    container_name: prysm
    restart: unless-stopped
    depends_on:
      - reth
    volumes:
      - ./Consensus:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --datadir=/data
      - --execution-endpoint=http://reth:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-host=0.0.0.0
      - --grpc-gateway-host=0.0.0.0
      - --blob-storage-layout=by-epoch
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --accept-terms-of-use
    ports:
      - 3500:3500
      - 4000:4000
EOF
echo -e "${GREEN}• Docker Compose file written.${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- Start Docker Stack ---
echo -e "${ORANGE}Starting Docker Compose stack...${NC}"
cd Ethereum
docker compose up -d --force-recreate --quiet-pull
cd ..
echo -e "${GREEN}• Docker Compose stack started.${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- Install Dozzle (Log Monitoring) ---
echo -e "${ORANGE}Installing Dozzle monitoring...${NC}"
if ! docker ps -a --format '{{.Names}}' | grep -q "^dozzle$"; then
  docker run -d \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -p 9999:8080 \
    --name dozzle \
    amir20/dozzle:latest >/dev/null 2>&1
  echo "• Dozzle installed."
else
  echo "• Dozzle container already exists, skipping."
fi
echo -e "${ORANGE}============================================================${NC}"

# --- Firewall Setup (Optional) ---
echo -e "${ORANGE}Configuring firewall rules (optional)...${NC}"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 30303/tcp >/dev/null 2>&1
  ufw allow 30303/udp >/dev/null 2>&1
  ufw allow 12000/udp >/dev/null 2>&1
  ufw allow 13000/tcp >/dev/null 2>&1
  ufw allow 9999/tcp >/dev/null 2>&1  # Dozzle
  ufw deny from any to any port 8551 proto tcp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1
  ufw reload >/dev/null 2>&1
  echo "• Base firewall rules configured."
else
  echo "• UFW not installed. Skipping firewall setup."
fi
echo -e "${ORANGE}============================================================${NC}"

# --- Node Status ---
echo -e "${ORANGE}ETHEREUM SEPOLIA NODE STATUS (Reth)${NC}"
echo -e "${ORANGE}============================================================${NC}"
echo -e "${GREEN}Local (Aztec node on this VPS)${NC}"
echo "• Sepolia RPC    : ✔ http://localhost:8545/"
echo "• Beacon RPC     : ✔ http://localhost:3500/"
echo -e "\n${GREEN}Remote (Aztec node on different VPS)${NC}"
echo "• Sepolia RPC    : ✔ http://$(hostname -I | awk '{print $1}'):8545/"
echo "• Beacon RPC     : ✔ http://$(hostname -I | awk '{print $1}'):3500/"
echo -e "\n${GREEN}Monitoring logs${NC}"
echo "• Dozzle         : ✔ http://$(hostname -I | awk '{print $1}'):9999/"
echo -e "${ORANGE}============================================================${NC}"

# --- Footer ---
echo -e "${ORANGE}SETUP COMPLETE - CREED'S TOOLS${NC}"
echo -e "${ORANGE}------------------------------------------------------------${NC}"
echo "• Need help? Reach out:"
printf "• %-9s : @web3.creed\n" "Discord"
printf "• %-9s : @web3_creed(Suspended Right Now)\n" "Twitter"
echo -e "${ORANGE}============================================================${NC}"
