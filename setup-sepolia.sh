#!/bin/bash

# --- Colors ---
NC='\033[0m'
ORANGE='\033[38;5;208m'
RED='\033[31m'
CYAN='\033[36m'
GREEN='\033[32m'
GRAY='\033[90m'

SUCCESS=true

# --- Banner ---
echo -e "${ORANGE}============================================================${NC}"
echo -e "${ORANGE}      ETHEREUM SEPOLIA NODE INSTALLER (Reth)${NC}"
echo -e "${ORANGE}                by Creed${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- System Check ---
echo -e "${ORANGE}Recommended System Specifications:${NC}"
echo "• CPU: 6 Cores"
echo "• RAM: 16 GB"
echo "• Storage: 1TB SSD"
echo -e "${ORANGE}============================================================${NC}"
echo -e "${ORANGE}Checking your system resources...${NC}"

# Use current directory for storage check
AVAILABLE_SPACE=$(df -BG --output=avail . | tail -1 | tr -d 'G ')
MOUNT_POINT=$(df -h . | awk 'NR==2 {print $6}')
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')

echo "Your System Resources:"
echo "• Checked mount point: $MOUNT_POINT"
echo "• Available Storage: ${AVAILABLE_SPACE}G"
echo "• CPU Cores: ${CPU_CORES}"
echo "• Total RAM: ${TOTAL_RAM}GB"

WARNING=""
if [[ ${AVAILABLE_SPACE} -lt 975 ]]; then
  WARNING+="${RED}• Low storage space detected (minimum 1TB required)${NC}\n"
fi
if [[ ${CPU_CORES} -lt 6 ]]; then
  WARNING+="${RED}• Insufficient CPU cores detected (minimum 6 required)${NC}\n"
fi
if [[ ${TOTAL_RAM} -lt 16 ]]; then
  WARNING+="${RED}• Insufficient RAM detected (minimum 16GB required)${NC}\n"
fi

if [[ -n "$WARNING" ]]; then
  echo -e "${RED}Potential Issues Found:${NC}"
  printf "$WARNING"
  echo "What would you like to do?"
  echo -e "${CYAN}1: Continue installation despite warnings${NC}"
  echo -e "${CYAN}2: Abort installation${NC}"
  echo -n "• Enter your choice (1-2): "
  read -r CHOICE
  case "$CHOICE" in
    1)
      echo "Continuing installation..."
      ;;
    2)
      echo "Installation aborted by user."
      SUCCESS=false
      ;;
    *)
      echo "Invalid choice. Aborting installation."
      SUCCESS=false
      ;;
  esac
fi

if ! $SUCCESS; then
  echo -e "${RED}Setup aborted due to system resource warnings or user abort.${NC}"
else

# --- Start Peak Storage Monitor ---
STORAGE_BEFORE=$(df -BG --output=used . | tail -1 | tr -d 'G ')
PEAK_STORAGE_FILE=$(mktemp)
echo "$STORAGE_BEFORE" > "$PEAK_STORAGE_FILE"

echo -e "${ORANGE}Starting peak storage monitor in the background...${NC}"
{
  PEAK_SO_FAR=$STORAGE_BEFORE
  while ps -p $$ > /dev/null; do
    CURRENT_USED=$(df -BG --output=used . | tail -1 | tr -d 'G ' || echo "$PEAK_SO_FAR")
    if (( CURRENT_USED > PEAK_SO_FAR )); then
      PEAK_SO_FAR=$CURRENT_USED
      echo "$PEAK_SO_FAR" > "$PEAK_STORAGE_FILE"
    fi
    sleep 2
  done
} &
MONITOR_PID=$!

echo -e "${ORANGE}============================================================${NC}"

# --- Prerequisites ---
echo -e "${ORANGE}Checking and installing prerequisites...${NC}"

install_apt_package_if_needed() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "• $1 not found. Installing..."
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y "$1" >/dev/null 2>&1 || {
      echo -e "${RED}Failed to install $1${NC}"
      SUCCESS=false
    }
  else
    echo "• $1 already installed."
  fi
}

# --- Docker & Compose ---
if $SUCCESS; then
  echo -e "${ORANGE}Checking for Docker and Docker Compose...${NC}"
  if ! command -v docker >/dev/null 2>&1; then
    echo "• Docker not found. Installing prerequisites..."
    curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash || SUCCESS=false
  fi

  if ! sudo docker compose version >/dev/null 2>&1; then
    echo "• Docker Compose plugin not found. Installing prerequisites..."
    curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash || SUCCESS=false
  fi

  if $SUCCESS; then
    echo "• Docker and Compose are installed."
  fi
fi

# --- zstd ---
if $SUCCESS; then
  install_apt_package_if_needed zstd
fi

# --- pv (for progress bar) ---
if $SUCCESS; then
  if ! command -v pv >/dev/null 2>&1; then
    echo -e "${CYAN}• pv not found. Installing it now for a progress bar...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y pv >/dev/null 2>&1 && echo "• 'pv' installed." || echo "• Could not install 'pv'. Progress bar will be omitted."
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y epel-release >/dev/null 2>&1
      sudo yum install -y pv >/dev/null 2>&1 && echo "• 'pv' installed." || echo "• Could not install 'pv'. Progress bar will be omitted."
    else
      echo "• Could not install 'pv'. Progress bar will be omitted."
    fi
  else
    echo "• pv (for progress bar) already installed."
  fi
fi

# --- Directory Structure ---
if $SUCCESS; then
  echo -e "${ORANGE}Creating directory structure...${NC}"
  mkdir -p Ethereum/Execution Ethereum/Consensus || {
    echo -e "${RED}Failed to create directories.${NC}"
    SUCCESS=false
  }
  if $SUCCESS; then
    echo "• Directory structure ready."
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Snapshot Section using curl streaming ---
if $SUCCESS; then

  echo -e "${ORANGE}Fetching latest Reth snapshot for Sepolia...${NC}"
  BLOCK_NUMBER=$(curl -s "https://snapshots.ethpandaops.io/sepolia/reth/latest")

  if [ -z "$BLOCK_NUMBER" ]; then
    echo -e "${RED}ERROR: No Reth snapshot available for Sepolia. Please check the snapshot service.${NC}"
    SUCCESS=false
  fi
fi

if $SUCCESS; then
  SNAPSHOT_URL="https://snapshots.ethpandaops.io/sepolia/reth/$BLOCK_NUMBER/snapshot.tar.zst"
  echo "Snapshot URL: $SNAPSHOT_URL"

  # Get snapshot size for progress bar ETA and percentage
  echo "• Getting snapshot size for progress bar..."
  SNAPSHOT_SIZE=$(curl -sI "$SNAPSHOT_URL" | grep -i 'content-length' | awk '{print $2}' | tr -d '\r')

  cd Ethereum/Execution || {
    echo -e "${RED}ERROR: Ethereum/Execution directory not found.${NC}"
    SUCCESS=false
  }
fi

if $SUCCESS; then
  echo -e "${ORANGE}• Downloading and extracting snapshot (streaming)...${NC}"

  # Clean out previous contents
  rm -rf ./*

  # Use curl | pv | tar streaming pipeline with full progress details
  if command -v pv >/dev/null 2>&1 && [ -n "$SNAPSHOT_SIZE" ]; then
    echo "• Snapshot size found. Starting download with full progress details..."
    # Use -pterb for: percentage, time, eta, rate, bytes
    # Added --retry and --continue-at flags to make the download more robust.
    curl -L --retry 5 --retry-delay 2 --continue-at - "$SNAPSHOT_URL" | pv -pterb -s "$SNAPSHOT_SIZE" | tar -I zstd -xf - || SUCCESS=false
  elif command -v pv >/dev/null 2>&1; then
    # Fallback if size couldn't be determined
    echo "• Could not determine snapshot size. Progress bar will be limited."
    curl -L --retry 5 --retry-delay 2 --continue-at - "$SNAPSHOT_URL" | pv | tar -I zstd -xf - || SUCCESS=false
  else
    # Fallback if pv is not installed
    echo "• pv not installed. No progress bar will be shown."
    curl -L --retry 5 --retry-delay 2 --continue-at - "$SNAPSHOT_URL" | tar -I zstd -xf - || SUCCESS=false
  fi

  cd ../.. || true

  if $SUCCESS; then
    echo -e "${GREEN}Snapshot imported successfully.${NC}"
  else
    echo -e "${RED}ERROR: Snapshot download or extraction failed.${NC}"
  fi
fi

# --- Generate JWT Secret ---
if $SUCCESS; then
  echo -e "${ORANGE}Generating JWT secret...${NC}"
  if [ -f Ethereum/jwt.hex ]; then
    echo "• JWT secret already exists, skipping."
  else
    openssl rand -hex 32 | tr -d "\n" > Ethereum/jwt.hex || {
      echo -e "${RED}Failed to generate JWT secret.${NC}"
      SUCCESS=false
    }
    if $SUCCESS; then
      echo "• JWT secret created."
    fi
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Write Docker Compose File ---
if $SUCCESS; then
  echo -e "${ORANGE}Writing Docker Compose file...${NC}"
  cat > Ethereum/docker-compose.yml <<'EOF'
services:
  # 1. Execution Client (Reth)
  reth:
    image: ghcr.io/paradigmxyz/reth:latest
    container_name: reth
    restart: unless-stopped
    volumes:
      - ./Execution:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      # Basic node configuration
      - node
      - --chain=sepolia
      - --full
      - --datadir=/data

      # Pruning Configuration: Keeps ~1 month of history to save disk space.
      - --prune.senderrecovery.distance=216000
      - --prune.transactionlookup.distance=216000
      - --prune.receipts.distance=216000
      - --prune.accounthistory.distance=216000
      - --prune.storagehistory.distance=216000
      - --prune.bodies.distance=216000

      # RPC & Engine API Configuration
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
      - "8545:8545"
      - "8546:8546"

  # 2. Consensus Client (Prysm)
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
      # Basic configuration and connection to the execution client (Reth).
      - --sepolia
      - --datadir=/data
      - --execution-endpoint=http://reth:8551
      - --jwt-secret=/data/jwt.hex

      # API and Checkpoint Sync Configuration
      - --rpc-host=0.0.0.0
      - --grpc-gateway-host=0.0.0.0
      - --blob-storage-layout=by-epoch
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --accept-terms-of-use
    ports:
      - "3500:3500"
      - "4000:4000"
EOF
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}• Docker Compose file written.${NC}"
  else
    echo -e "${RED}Failed to write Docker Compose file.${NC}"
    SUCCESS=false
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Start Docker Stack ---
if $SUCCESS; then
  echo -e "${ORANGE}Starting Docker Compose stack...${NC}"
  cd Ethereum || {
    echo -e "${RED}ERROR: Cannot enter Ethereum directory.${NC}"
    SUCCESS=false
  }
  if $SUCCESS; then
    docker compose up -d --force-recreate --quiet-pull || {
      echo -e "${RED}Failed to start Docker Compose stack.${NC}"
      SUCCESS=false
    }
    cd .. || true
    if $SUCCESS; then
      echo -e "${GREEN}• Docker Compose stack started.${NC}"
    fi
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Install Dozzle Log Monitor ---
if $SUCCESS; then
  echo -e "${ORANGE}Installing Dozzle monitoring...${NC}"
  if ! docker ps -a --format '{{.Names}}' | grep -q "^dozzle$"; then
    docker run -d \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -p 9999:8080 \
      --name dozzle \
      amir20/dozzle:latest >/dev/null 2>&1 && echo "• Dozzle installed." || echo "• Failed to install Dozzle."
  else
    echo "• Dozzle container already exists, skipping."
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Firewall Setup (Optional) ---
if $SUCCESS; then
  echo -e "${ORANGE}Configuring firewall rules (optional)...${NC}"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1
    ufw allow ssh >/dev/null 2>&1
    ufw allow 30303/tcp >/dev/null 2>&1
    ufw allow 30303/udp >/dev/null 2>&1
    ufw allow 12000/udp >/dev/null 2>&1
    ufw allow 13000/tcp >/dev/null 2>&1
    ufw allow 9999/tcp >/dev/null 2>&1  # Dozzle monitoring

    ufw deny 8545/tcp >/dev/null 2>&1
    ufw deny 3500/tcp >/dev/null 2>&1

    ufw deny from any to any port 8551 proto tcp >/dev/null 2>&1

    ufw --force enable >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    echo "• Base firewall rules configured."
  else
    echo "• UFW not installed. Skipping firewall setup."
  fi
fi

# --- Monitor Reth Sync Progress ---
if $SUCCESS; then
  # We define the function right before we use it for better readability.
  monitor_reth_sync() {
      echo "" # Add a blank line for spacing before the monitor starts.
      echo -e "${CYAN}• The node is now syncing (This screen refreshes automatically)${NC}"
      
      first_run=true

      # Main Monitoring Loop
      while true; do
          # This trap allows the user to press Ctrl+C to skip monitoring and continue.
          trap 'echo -e "\n\n${ORANGE}Monitoring skipped by user. Continuing setup...${NC}\n"; return' INT
          
          if [ "$first_run" = false ]; then
              printf "\033[5A" # Move cursor up 5 lines to overwrite the status block
          fi
          first_run=false

          SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' "http://localhost:8545")

          LATEST_FINISHED_LINE=$(docker logs reth 2>/dev/null | grep "Finished stage" | tail -1)
          FINISHED_STAGE_TEXT="${GRAY}Waiting for first stage to finish...${NC}"
          if [ -n "$LATEST_FINISHED_LINE" ]; then
              CLEAN_FINISHED_LINE=$(echo "$LATEST_FINISHED_LINE" | sed -e 's/\x1b\[[0-9;]*m//g')
              PARSED_STAGE_INFO=$(echo "$CLEAN_FINISHED_LINE" | grep -o 'pipeline_stages=[^ ]*' | cut -d'=' -f2)
              PARSED_STAGE_NAME=$(echo "$CLEAN_FINISHED_LINE" | grep -o 'stage=[^ ]*' | cut -d'=' -f2)
              if [ -n "$PARSED_STAGE_INFO" ] && [ -n "$PARSED_STAGE_NAME" ]; then
                  FINISHED_STAGE_TEXT=$(printf "${GREEN}%-7s (%s)${NC}" "$PARSED_STAGE_INFO" "$PARSED_STAGE_NAME")
              fi
          fi

          LATEST_RUNNING_LINE=$(docker logs reth 2>/dev/null | grep -E "Executing stage|Committed stage progress" | tail -1)
          RUNNING_STAGE_TEXT="${GRAY}Initializing...${NC}"
          if [ -n "$LATEST_RUNNING_LINE" ]; then
              CLEAN_RUNNING_LINE=$(echo "$LATEST_RUNNING_LINE" | sed -e 's/\x1b\[[0-9;]*m//g')
              RUNNING_STAGE_INFO=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'pipeline_stages=[^ ]*' | cut -d'=' -f2)
              RUNNING_STAGE_NAME=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'stage=[^ ]*' | cut -d'=' -f2)
              RUNNING_STAGE_PCT=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'stage_progress=[^ ]*' | cut -d'=' -f2)
              if [ -n "$RUNNING_STAGE_INFO" ] && [ -n "$RUNNING_STAGE_NAME" ]; then
                  if [ -n "$RUNNING_STAGE_PCT" ]; then
                      RUNNING_STAGE_TEXT=$(printf "${CYAN}%-7s (%s) | Progress: %s${NC}" "$RUNNING_STAGE_INFO" "$RUNNING_STAGE_NAME" "$RUNNING_STAGE_PCT")
                  else
                      RUNNING_STAGE_TEXT=$(printf "${CYAN}%-7s (%s)${NC}" "$RUNNING_STAGE_INFO" "$RUNNING_STAGE_NAME")
                  fi
              fi
          fi

          # The `\033[K` at the end of each line clears it from the cursor to the end.
          if echo "$SYNC_STATUS" | grep -q '"result":false'; then
              echo -e "${ORANGE}==================== RETH SYNC STATUS =====================\033[K${NC}"
              echo -e "${GREEN}Synced         - ✔ Synced\033[K${NC}"
              echo -e "${GREEN}Finished Stage - All stages complete.\033[K${NC}"
              echo -e "${GREEN}Current Stage  - Done.\033[K${NC}"
              echo -e "${ORANGE}============================================================\033[K${NC}"
              sleep 1
              break # Exit the loop
          else
              echo -e "${ORANGE}==================== RETH SYNC STATUS =====================\033[K${NC}"
              echo -e "${CYAN}Synced         - ⏳ In Progress...\033[K${NC}"
              echo -e "Finished Stage - $FINISHED_STAGE_TEXT\033[K"
              echo -e "Current Stage  - $RUNNING_STAGE_TEXT\033[K"
              echo -e "${ORANGE}============================================================\033[K${NC}"
          fi
          sleep 5
      done
      # Reset the trap and add a final newline for clean separation.
      trap - INT
      echo ""
  }
  # Now, call the function we just defined.
  monitor_reth_sync
fi

# --- Storage Summary ---
if $SUCCESS; then
  # Stop the background monitor
  kill "$MONITOR_PID" 2>/dev/null
  wait "$MONITOR_PID" 2>/dev/null || true

  # Read the final peak value and clean up
  PEAK_STORAGE_DURING_SETUP=$(cat "$PEAK_STORAGE_FILE")
  rm "$PEAK_STORAGE_FILE"

  STORAGE_AFTER=$(df -BG --output=used . | tail -1 | tr -d 'G ')

  if [ -n "$STORAGE_BEFORE" ] && [ -n "$PEAK_STORAGE_DURING_SETUP" ]; then
    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE}                    STORAGE SUMMARY${NC}"
    echo -e "${ORANGE}============================================================${NC}"
    printf "• Initial Storage Used:         %s\n" "${STORAGE_BEFORE}G"
    printf "• Peaked Storage During Setup:  ${CYAN}%s${NC}\n" "${PEAK_STORAGE_DURING_SETUP}G"
    printf "• Final Storage Used:           %s\n" "${STORAGE_AFTER}G"
  fi
fi

# --- Node Status Display ---
if $SUCCESS; then
  echo -e "${ORANGE}============================================================${NC}"
  echo -e "${ORANGE}ETHEREUM SEPOLIA NODE STATUS (Reth)${NC}"
  echo -e "${ORANGE}============================================================${NC}"
  echo -e "${GREEN}Local (Aztec node on this VPS)${NC}"
  echo "• Sepolia RPC    : ✔ http://localhost:8545/"
  echo "• Beacon RPC     : ✔ http://localhost:3500/"
  echo -e "\n${GREEN}Remote (Aztec node on different VPS)${NC}"
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  echo "• Sepolia RPC    : ✔ http://$LOCAL_IP:8545/"
  echo "• Beacon RPC     : ✔ http://$LOCAL_IP:3500/"
  echo -e "\n${GREEN}Monitoring logs${NC}"
  echo "• Dozzle         : ✔ http://$LOCAL_IP:9999/"
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Footer ---
if $SUCCESS; then
  echo -e "${ORANGE}SETUP COMPLETE - CREED'S TOOLS${NC}"
  echo -e "${ORANGE}------------------------------------------------------------${NC}"
  echo "• Need help? Reach out:"
  printf "• %-9s : @web3.creed\n" "Discord"
  printf "• %-9s : @web3mrcat\n" "Twitter"
  echo -e "${ORANGE}============================================================${NC}"
else
  echo -e "${RED}Installation did not complete successfully.${NC}"
  echo -e "${RED}Please resolve errors and rerun the script.${NC}"
fi

fi # End main SUCCESS check from system pre-check
