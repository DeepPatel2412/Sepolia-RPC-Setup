#!/bin/bash
set -e

echo "🔍 [0/8] Checking for Docker and Docker Compose..."

if ! command -v docker >/dev/null 2>&1; then
  echo "🐳 Docker not found. Installing prerequisites..."
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi

if ! sudo docker compose version >/dev/null 2>&1; then
  echo "🐳 Docker Compose plugin not found. Installing prerequisites..."
  curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/install-prerequisites.sh | bash
fi

echo "✅ Docker and Compose are installed. Proceeding with Sepolia node setup..."

# ---- 1. Create Directory Structure ----
echo "🔧 [1/8] Creating directory structure..."
mkdir -p Ethereum/Execution Ethereum/Consensus
echo "✅ Directory structure ready."

# ---- 2. Generate JWT Secret ----
echo "🔧 [2/8] Generating JWT secret..."
if [ ! -f Ethereum/jwt.hex ]; then
  openssl rand -hex 32 | tr -d "\n" > Ethereum/jwt.hex
  echo "✅ JWT secret created."
else
  echo "ℹ️  JWT secret already exists, skipping."
fi

# ---- 3. Create Default Whitelist File ----
echo "🔧 [3/8] Creating whitelist file..."
if [ ! -f Ethereum/whitelist.lst ]; then
  echo "127.0.0.1/32" > Ethereum/whitelist.lst
  echo "✅ Whitelist file created."
else
  echo "ℹ️  Whitelist file already exists, skipping."
fi

# ---- 4. Write Docker Compose File ----
echo "🔧 [4/8] Writing Docker Compose file..."
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
      - --blob-pruning
      - --blob-retention=864000
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
      - --blob-retention-epochs=9000
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
echo "✅ Docker Compose file written."

# ---- 5. Write HAProxy Config ----
echo "🔧 [5/8] Writing HAProxy config..."
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
echo "✅ HAProxy config written."

# ---- 6. Start Docker Compose Stack ----
echo "🔧 [6/8] Starting Docker Compose stack..."
cd Ethereum
sudo docker compose up -d
echo "✅ Docker Compose stack started."

# ---- 7. Set Up UFW Firewall (Best Practice) ----
echo "🔧 [7/8] Configuring UFW firewall rules..."
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
  sudo ufw status verbose
  echo "✅ UFW firewall configured."
else
  echo "⚠️  UFW not installed. Skipping firewall setup."
fi

echo ""
echo "🎉 All steps complete!"
echo "-----------------------------------------------------------"
echo "   - Reth (Execution): http://<your-server>/reth/"
echo "   - Prysm (Consensus): http://<your-server>/prysm/"
echo ""
echo "👉 To whitelist more IPs: edit Ethereum/whitelist.lst then:"
echo "   sudo docker restart haproxy"
echo ""
echo "💡 For L2/L3 use:"
echo "   --l1-rpc-urls http://<your-server>/reth/"
echo "   --l1-consensus-host-urls http://<your-server>/prysm/"
echo ""
echo "🛡️  Firewall allows SSH/HTTP/HTTPS only"
echo "🗄️  Disk: ~200-250GB SSD recommended for 1 month retention"
echo "-----------------------------------------------------------"
