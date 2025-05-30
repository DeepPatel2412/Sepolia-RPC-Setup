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
echo -e "· CPU: 4+ cores"
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
[[ ${CPU_CORES} -lt 4 ]] && WARNING+="· ${RED}Insufficient CPU cores detected${NC}\n"
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

# ---- 3. Create Default Whitelist File ----
echo -e "${CYAN}Creating whitelist file...${NC}"
if [ ! -f Ethereum/whitelist.lst ]; then
  echo "127.0.0.1/32" > Ethereum/whitelist.lst
  echo -e "${GREEN}Whitelist file created.${NC}"
else
  echo -e "${YELLOW}Whitelist file already exists, skipping.${NC}"
fi

# ---- 4. Write Docker Compose File ----
echo -e "${CYAN}Writing Docker Compose file...${NC}"
cat > Ethereum/docker-compose.yml <<EOF
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
      - --ws
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --http.api=eth,net,web3,admin
      - --ws.api=eth,net,web3,admin
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

  haproxy:
    image: haproxy:2.8
    container_name: haproxy
    restart: unless-stopped
    depends_on:
      - reth
      - prysm
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
      - ./whitelist.lst:/etc/haproxy/whitelist.lst
    ports:
      - 80:80
      - 443:443
EOF
echo -e "${GREEN}Docker Compose file written.${NC}"

# ---- 5. Write HAProxy Config ----
echo -e "${CYAN}Writing HAProxy config...${NC}"
cat > Ethereum/haproxy.cfg <<EOF
global
    maxconn 50000
    nbthread 4
    cpu-map 1-4 0-3

defaults
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend http-in
    bind *:80
    bind *:443
    mode http
    acl valid_ip src -f /etc/haproxy/whitelist.lst
    http-request deny if !valid_ip

    use_backend reth_backend if { path_beg /reth/ }
    use_backend prysm_backend if { path_beg /prysm/ }

backend reth_backend
    mode http
    balance roundrobin
    server reth1 reth:8545 maxconn 10000 check inter 5s

backend prysm_backend
    mode http
    balance leastconn
    server prysm1 prysm:3500 maxconn 5000 check inter 5s
EOF
echo -e "${GREEN}HAProxy config written.${NC}"

# ---- 6. Start Docker Compose Stack ----
echo -e "${CYAN}Starting Docker Compose stack...${NC}"
cd Ethereum
sudo docker compose up -d
echo -e "${GREEN}Docker Compose stack started.${NC}"

# ---- 7. Set Up UFW Firewall (Best Practice) ----
echo -e "${CYAN}Configuring UFW firewall rules...${NC}"
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 9999/tcp
  sudo ufw --force enable
  sudo ufw status verbose
  echo -e "${GREEN}UFW firewall configured.${NC}"
else
  echo -e "${YELLOW}UFW not installed. Skipping firewall setup.${NC}"
fi

# ---- 8. Install Dozzle Monitoring ----
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

echo -e "${BOLD}Local (Aztec in same VPS)${NC}"
echo -e "· Sepolia RPC    : ${GREEN}✔${NC} ${YELLOW}http://127.0.0.1/reth/${NC}"
echo -e "· Beacon RPC     : ${GREEN}✔${NC} ${YELLOW}http://127.0.0.1/prysm/${NC}"

echo -e "\n${BOLD}Remote (Aztec in other VPS)${NC}"
echo -e "· Sepolia RPC    : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}/reth/${NC}"
echo -e "· Beacon RPC     : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}/prysm/${NC}"

echo -e "\n${BOLD}Monitoring${NC}"
echo -e "· Dozzle         : ${GREEN}✔${NC} ${YELLOW}http://${REMOTE_IP}:9999/${NC}"

echo -e "\n${BOLD}Whitelist file${NC}"
echo -e "· ${YELLOW}Ethereum/whitelist.lst${NC}"

echo -e "${CYAN}----------------------------------------${NC}"
echo -e "${BOLD}Example L2/L3 usage:${NC}"
echo -e "${CYAN}----------------------------------------${NC}"
echo -e "${GRAY}--l1-rpc-urls http://${REMOTE_IP}/reth/"
echo -e "--l1-consensus-host-urls http://${REMOTE_IP}/prysm/${NC}"
echo -e "${CYAN}----------------------------------------${NC}"

echo -e "${BOLD}To whitelist more IPs:${NC} edit ${YELLOW}Ethereum/whitelist.lst${NC} then:"
echo -e "  sudo docker restart haproxy"

echo -e "${CYAN}----------------------------------------${NC}"
echo -e "${BOLD}Firewall:${NC} allows SSH/HTTP/HTTPS only"
echo -e "${CYAN}========================================${NC}"

# ---- 9. Offer to Add Whitelist IP ----
echo ""
read -p "Add IP to whitelist for remote access? [Y/n]: " ADD_WL
ADD_WL=${ADD_WL:-Y}

if [[ "$ADD_WL" =~ ^[Yy]$ ]]; then
  echo "ℹ️  Your remote IP appears to be: ${REMOTE_IP}"
  read -p "Enter IP/CIDR to whitelist (default ${REMOTE_IP}/32): " WL_IP
  WL_IP=${WL_IP:-${REMOTE_IP}/32}

  if [[ "$WL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
    if grep -qxF "$WL_IP" Ethereum/whitelist.lst; then
      echo -e "${YELLOW}IP $WL_IP is already whitelisted.${NC}"
    else
      echo "$WL_IP" >> Ethereum/whitelist.lst
      echo -e "${GREEN}Added $WL_IP to whitelist.${NC}"
      echo "Restarting HAProxy container to apply changes..."
      sudo docker restart haproxy
      echo -e "${GREEN}HAProxy restarted.${NC}"
    fi
  else
    echo -e "${RED}Invalid IP format. Please edit Ethereum/whitelist.lst manually.${NC}"
  fi
fi

echo ""
echo -e "${GREEN}Setup complete. Enjoy your Sepolia node!${NC}"
