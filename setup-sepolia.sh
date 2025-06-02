#!/bin/bash
set -e

# ---- Colors ----
NC='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
GRAY='\033[90m'

# ---- Pre-flight Check ----
echo -e "${CYAN}========================================"
echo -e "     ETHEREUM SEPOLIA NODE INSTALLER"
echo -e "========================================${NC}"
echo -e "${BOLD}Recommended System Specifications:${NC}"
echo -e "· Storage: 750GB-1TB SSD"
echo -e "· CPU: 6+ cores"
echo -e "· RAM: 16GB+"
echo -e "${CYAN}----------------------------------------${NC}"
echo "Checking your system resources..."

AVAILABLE_SPACE=$(df -BG --output=avail / | tail -1 | tr -d ' ')
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')

echo -e "\n${BOLD}Your System Resources:${NC}"
echo -e "· Available Storage: ${AVAILABLE_SPACE}B"
echo -e "· CPU Cores: ${CPU_CORES}"
echo -e "· Total RAM: ${TOTAL_RAM}GB"

WARNING=""
[[ ${AVAILABLE_SPACE%G} -lt 750 ]] && WARNING+="· ${RED}Low storage space detected${NC}\n"
[[ ${CPU_CORES} -lt 6 ]] && WARNING+="· ${RED}Insufficient CPU cores detected${NC}\n"
[[ ${TOTAL_RAM} -lt 16 ]] && WARNING+="· ${RED}Insufficient RAM detected${NC}\n"

if [[ -n "$WARNING" ]]; then
    echo -e "\n${RED}Potential Issues Found:${NC}"
    printf "$WARNING"
    read -p "Continue installation despite warnings? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    [[ "$CONTINUE" =~ [yY] ]] || exit 1
fi

echo -e "${CYAN}----------------------------------------${NC}"

# ---- 0. Check Docker and Compose ----
echo -e "${CYAN}Checking for Docker and Docker Compose...${NC}"

if ! command -v docker >/dev/null 2>&1; then
  echo -e "${YELLOW}Docker not found. Installing prerequisites...${NC}"
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi

if ! sudo docker compose version >/dev/null 2>&1; then
  echo -e "${YELLOW}Docker Compose plugin not found. Installing prerequisites...${NC}"
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi

echo -e "${GREEN}Docker and Compose are installed. Proceeding with Sepolia node setup...${NC}"

# ---- 1. Create Directory Structure ----
echo -e "${CYAN}Creating directory structure...${NC}"
mkdir -p Ethereum/Execution Ethereum/Consensus
echo -e "${GREEN}Directory structure ready.${NC}"

# ---- 2. Generate JWT Secret ----
echo -e "${CYAN}Generating JWT secret...${NC}"
if [ ! -f Ethereum/jwt.hex ]; then
  openssl rand -hex 32 | tr -d "\n" > Ethereum/jwt.hex
  echo -e "${GREEN}JWT secret created.${NC}"
else
  echo -e "${YELLOW}JWT secret already exists, skipping.${NC}"
fi

# ---- 3. Write Docker Compose File ----
echo -e "${CYAN}Writing Docker Compose file...${NC}"
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
echo -e "${GREEN}Docker Compose file written.${NC}"

# ---- 4. Start Docker Compose Stack ----
echo -e "${CYAN}Starting Docker Compose stack (reth & prysm)...${NC}"
cd Ethereum
sudo docker compose up -d --force-recreate reth prysm
echo -e "${GREEN}Docker Compose stack started.${NC}"

# ---- 5. Add UFW Firewall Rules (DO NOT RESET) ----
echo -e "${CYAN}Configuring UFW firewall rules (adding only, not resetting)...${NC}"
if command -v ufw >/dev/null 2>&1; then
  # Allow Ethereum/Prysm P2P networking
  sudo ufw allow 30303/tcp
  sudo ufw allow 30303/udp
  sudo ufw allow 12000/udp
  sudo ufw allow 13000/tcp

  # Allow Dozzle monitoring (optional)
  sudo ufw allow 9999/tcp

  # Prompt for and whitelist API access
  read -p "How many IPs/CIDR ranges do you want to whitelist for node API access? " NUM_IPS
  NUM_IPS=${NUM_IPS:-0}
  for ((i=1; i<=NUM_IPS; i++)); do
    while true; do
      read -p "Enter IP/CIDR #$i (e.g., 192.168.1.0/24): " IP_CIDR_RAW
      IP_CIDR=$(echo "$IP_CIDR_RAW" | xargs) # trim whitespace
      if [[ "$IP_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
         [[ "$IP_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
        sudo ufw allow from "$IP_CIDR" to any port 8545 proto tcp
        sudo ufw allow from "$IP_CIDR" to any port 8546 proto tcp
        sudo ufw allow from "$IP_CIDR" to any port 3500 proto tcp
        sudo ufw allow from "$IP_CIDR" to any port 4000 proto tcp
        echo -e "${GREEN}Whitelisted ${YELLOW}$IP_CIDR${GREEN} for node API access${NC}"
        break
      else
        echo -e "${RED}Invalid IP or CIDR format. Example valid: 38.143.58.227 or 38.143.58.227/32 or 192.168.1.0/24${NC}"
      fi
    done
  done

  sudo ufw --force enable
  sudo ufw status numbered
else
  echo -e "${YELLOW}UFW not installed. Skipping firewall setup.${NC}"
fi

# ---- 6. Install Dozzle Monitoring ----
echo -e "${CYAN}Installing Dozzle monitoring...${NC}"
cd ..
if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^dozzle$"; then
  sudo docker run -d \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -p 9999:8080 \
    --name dozzle \
    amir20/dozzle:latest
  echo -e "${GREEN}Dozzle installed.${NC}"
else
  echo -e "${YELLOW}Dozzle container already exists, skipping.${NC}"
fi

# ---- Get Server IPs ----
LOCAL_IP="127.0.0.1"
SERVER_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -4 -s ifconfig.me || echo $SERVER_IP)
REMOTE_IP=$PUBLIC_IP

# ---- Final Output ----
echo -e "${CYAN}========================================"
echo -e "         ETHEREUM SEPOLIA NODE STATUS"
echo -e "========================================${NC}"

echo -e "${BOLD}Local (on this VPS)${NC}"
echo -e "· Sepolia RPC    : ${GREEN}✔${NC} ${YELLOW}http://127.0.0.1:8545/${NC}"
echo -e "· Beacon RPC     : ${GREEN}✔${NC} ${YELLOW}http://127.0.0.1:3500/${NC}"

echo -e "\n${BOLD}Remote (from another machine)${NC}"
echo -e "· Sepolia RPC    : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}:8545/${NC}"
echo -e "· Beacon RPC     : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}:3500/${NC}"

echo -e "\n${BOLD}Monitoring${NC}"
echo -e "· Dozzle         : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}:9999/${NC}"

echo -e "${BOLD}Firewall:${NC} allows SSH, Dozzle, node P2P, and whitelisted API ports only"
echo -e "${CYAN}========================================${NC}"

echo ""
echo -e "${GREEN}Setup complete. Enjoy your Sepolia node!${NC}"
