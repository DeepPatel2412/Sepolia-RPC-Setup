#!/bin/bash

main() {
    clear

    # ---- Colors ----
    NC='\033[0m'
    ORANGE='\033[38;5;208m'
    RED='\033[31m'
    CYAN='\033[36m'

    # ---- Branded Header ----
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${ORANGE}             ETHEREUM SEPOLIA NODE INSTALLER${NC}"
    echo -e "${ORANGE}                       by Creed${NC}"
    echo -e "${CYAN}============================================================${NC}"

    # ---- Pre-flight Check ----
    echo -e "${ORANGE}Recommended System Specifications:${NC}"
    echo "• Storage: 750GB-1TB SSD"
    echo "• CPU: 6+ cores"
    echo "• RAM: 16GB+"

    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}Checking your system resources...${NC}\n"

    AVAILABLE_SPACE=$(df -BG --output=avail / | tail -1 | tr -d ' ')
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')

    echo "Your System Resources:"
    echo "• Available Storage: ${AVAILABLE_SPACE}B"
    echo "• CPU Cores: ${CPU_CORES}"
    echo "• Total RAM: ${TOTAL_RAM}GB"

    WARNING=""
    [[ ${AVAILABLE_SPACE%G} -lt 750 ]] && WARNING+="${RED}Low storage space detected${NC}\n"
    [[ ${CPU_CORES} -lt 6 ]] && WARNING+="${RED}Insufficient CPU cores detected${NC}\n"
    [[ ${TOTAL_RAM} -lt 16 ]] && WARNING+="${RED}Insufficient RAM detected${NC}\n"

    if [[ -n "$WARNING" ]]; then
        echo -e "${RED}• Potential Issues Found:${NC}"
        printf "$WARNING"
        echo "What would you like to do?"
        echo -e "${CYAN}1: Continue installation despite warnings${NC}"
        echo -e "${CYAN}2: Abort installation${NC}"
        echo -n "• Enter your choice (1-2): "
        read CHOICE
        case "$CHOICE" in
            1)
                # Continue
                ;;
            2)
                echo "Installation aborted by user."
                return 1
                ;;
            *)
                echo "Invalid choice. Aborting installation."
                return 1
                ;;
        esac
    fi

    echo -e "${ORANGE}============================================================${NC}"

    # ---- Docker & Compose Check ----
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

    # ---- Directory Structure ----
    echo -e "${ORANGE}Creating directory structure...${NC}"
    mkdir -p Ethereum/Execution Ethereum/Consensus
    echo "• Directory structure ready."

    # ---- Install pv if not present (for progress bar) ----
    if ! command -v pv >/dev/null 2>&1; then
        echo -e "${CYAN}Progress bar tool 'pv' not found. Installing it now...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y pv >/dev/null 2>&1
            echo "• 'pv' installed for progress bar."
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y epel-release >/dev/null 2>&1 && sudo yum install -y pv >/dev/null 2>&1
            echo "• 'pv' installed for progress bar."
        else
            echo "• Could not install 'pv'. Progress bar will be limited."
        fi
    fi

    # ---- Reth Snapshot Import ----
    echo -e "${ORANGE}Step 1: Downloading Sepolia Reth snapshot...${NC}"
    echo -e "${ORANGE}This will take several hours. Please wait and do not close the terminal.${NC}"
    echo -e "${ORANGE}Progress will be shown below:${NC}"
    cd Ethereum/Execution
    rm -rf ./*  # Clear existing data

    export BLOCK_NUMBER=$(curl -s https://snapshots.ethpandaops.io/sepolia/reth/latest)
    SNAPSHOT_URL="https://snapshots.ethpandaops.io/sepolia/reth/$BLOCK_NUMBER/snapshot.tar.zst"

    # Get snapshot size (for estimation)
    SNAPSHOT_SIZE_BYTES=$(curl -sI "$SNAPSHOT_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r')
    SNAPSHOT_SIZE_GB=$(echo "scale=2; $SNAPSHOT_SIZE_BYTES / 1024 / 1024 / 1024" | bc)
    echo -e "${CYAN}Snapshot size: ${SNAPSHOT_SIZE_GB} GB${NC}"

    START_TIME=$(date +%s)

    if command -v pv >/dev/null 2>&1; then
        echo -e "${CYAN}Using 'pv' for progress bar...${NC}"
        if ! curl -s -L "$SNAPSHOT_URL" | pv -s $SNAPSHOT_SIZE_BYTES | tar -I zstd -xvf - --strip-components=1; then
            echo -e "${RED}ERROR: Snapshot extraction failed. Please check your network and try again.${NC}"
            cd ../..
            exit 1
        fi
    elif curl --version | grep -q "progress-meter"; then
        echo -e "${CYAN}Using curl with progress meter...${NC}"
        if ! curl -L --progress-bar "$SNAPSHOT_URL" | tar -I zstd -xvf - --strip-components=1; then
            echo -e "${RED}ERROR: Snapshot extraction failed. Please check your network and try again.${NC}"
            cd ../..
            exit 1
        fi
    else
        echo -e "${CYAN}No progress bar available. Please be patient.${NC}"
        echo -e "${CYAN}Estimated total size: ${SNAPSHOT_SIZE_GB} GB${NC}"
        # Start a background process to log progress every 60 seconds
        (
            while true; do
                sleep 60
                CURRENT_SIZE=$(du -sb . | awk '{print $1}')
                PERCENT=$(echo "scale=2; 100*$CURRENT_SIZE/$SNAPSHOT_SIZE_BYTES" | bc)
                ELAPSED=$(( $(date +%s) - $START_TIME ))
                if [[ $ELAPSED -gt 0 && $PERCENT != "0" ]]; then
                    ESTIMATED_TOTAL=$(( ELAPSED * 100 / $(echo "$PERCENT" | awk '{print int($1)}') ))
                    REMAINING=$(( ESTIMATED_TOTAL - ELAPSED ))
                    echo -e "${CYAN}Progress: ${PERCENT}% (${CURRENT_SIZE} bytes) | Time left: $(date -u -d @$REMAINING +'%H:%M:%S')${NC}"
                fi
            done
        ) &
        PID=$!
        if ! curl -s -L "$SNAPSHOT_URL" | tar -I zstd -xvf - --strip-components=1; then
            echo -e "${RED}ERROR: Snapshot extraction failed. Please check your network and try again.${NC}"
            kill $PID 2>/dev/null || true
            cd ../..
            exit 1
        fi
        kill $PID 2>/dev/null || true
    fi
    cd ../..
    echo -e "${ORANGE}• Sepolia Reth snapshot imported.${NC}"

    # ---- JWT Secret ----
    echo -e "${ORANGE}Generating JWT secret...${NC}"
    if [ -d Ethereum/jwt.hex ]; then
      rm -rf Ethereum/jwt.hex
    fi
    if [ ! -f Ethereum/jwt.hex ]; then
      openssl rand -hex 32 | tr -d "\n" > Ethereum/jwt.hex
      echo "• JWT secret created."
    else
      echo "• JWT secret already exists, skipping."
    fi

    # ---- Docker Compose File ----
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
    echo "• Docker Compose file written."

    # ---- Start Docker Stack ----
    echo -e "${ORANGE}Starting Docker Compose stack...${NC}"
    cd Ethereum
    sudo docker compose up -d --force-recreate --quiet-pull reth prysm
    echo "• Docker Compose stack started."

    # ---- Dozzle Monitoring (Mandatory, no prompt) ----
    echo -e "${ORANGE}Installing Dozzle monitoring...${NC}"
    cd ..
    if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^dozzle$"; then
      sudo docker run -d \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 9999:8080 \
        --name dozzle \
        amir20/dozzle:latest >/dev/null 2>&1
      echo "• Dozzle installed."
    else
      echo "• Dozzle container already exists, skipping."
    fi

    # ---- Firewall Setup and Whitelist Function ----
    ufw_whitelist_ips() {
      echo -e "${ORANGE}============================================================${NC}"
      echo "• Enter IP address(es) separated by comma"
      echo "• Example: 192.168.1.15,203.0.113.42"
      echo -n "• IP addresses: "
      read IP_INPUT

      IFS=',' read -ra IP_LIST <<< "$IP_INPUT"
      for IP in "${IP_LIST[@]}"; do
        IP_CLEAN=$(echo "$IP" | xargs | cut -d'/' -f1)
        if [[ "$IP_CLEAN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          sudo ufw allow from "${IP_CLEAN}/32" to any port 8545 proto tcp >/dev/null 2>&1
          sudo ufw allow from "${IP_CLEAN}/32" to any port 3500 proto tcp >/dev/null 2>&1
          echo "• Whitelisted ${IP_CLEAN}/32"
        else
          echo "• Invalid IP: ${IP_CLEAN}"
        fi
      done
      sudo ufw reload >/dev/null 2>&1
    }

    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}Configuring firewall rules...${NC}"
    if command -v ufw >/dev/null 2>&1; then
      sudo ufw allow 30303/tcp >/dev/null 2>&1
      sudo ufw allow 30303/udp >/dev/null 2>&1
      sudo ufw allow 12000/udp >/dev/null 2>&1
      sudo ufw allow 13000/tcp >/dev/null 2>&1
      sudo ufw allow 9999/tcp >/dev/null 2>&1  # Dozzle
      sudo ufw deny from any to any port 8551 proto tcp >/dev/null 2>&1
      sudo ufw --force enable >/dev/null 2>&1
      sudo ufw reload >/dev/null 2>&1
      echo "• Base firewall rules configured."

      echo -e "${ORANGE}You should whitelist IPs for RPC/API access:${NC}"
      echo -e "${ORANGE}• Required for Aztec integration${NC}"
      echo "What would you like to do?"
      echo -e "${CYAN}1: Configure IP whitelisting now${NC}"
      echo -e "${CYAN}2: Skip IP whitelisting${NC}"
      echo -n "• Enter your choice (1-2): "
      read CHOICE
      case "$CHOICE" in
        1)
          ufw_whitelist_ips
          ;;
        2)
          echo "• Skipping IP whitelisting."
          ;;
        *)
          echo "• Invalid choice. Skipping IP whitelisting."
          ;;
      esac
    else
      echo "• UFW not installed. Skipping firewall setup."
    fi

    # ---- Get Server IPs ----
    LOCAL_IP="127.0.0.1"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -4 -s ifconfig.me || echo $SERVER_IP)
    REMOTE_IP=$PUBLIC_IP

    # ---- Node Status ----
    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}         ETHEREUM SEPOLIA NODE STATUS${NC}"
    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}Local (Aztec node on this VPS)${NC}"
    echo "• Sepolia RPC    : ✔ http://localhost:8545/"
    echo "• Beacon RPC     : ✔ http://localhost:3500/"
    echo -e "\n${ORANGE}Remote (Aztec node on another VPS)${NC}"
    echo "• Sepolia RPC    : ✔ http://${REMOTE_IP}:8545/"
    echo "• Beacon RPC     : ✔ http://${REMOTE_IP}:3500/"
    echo -e "\n${ORANGE}Monitoring${NC}"
    echo "• Dozzle         : ✔ http://${REMOTE_IP}:9999/"
    echo -e "${ORANGE}============================================================${NC}"

    # ---- Branded Footer ----
    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}         SETUP COMPLETE - CREED'S TOOLS${NC}"
    echo -e "${ORANGE}------------------------------------------------------------${NC}"
    echo "• Need help? Reach out:"
printf "• %-9s : @web3.creed\n" "Discord"
printf "• %-9s : @web3_creed\n" "Twitter"
    echo -e "${ORANGE}============================================================${NC}"
}

main
