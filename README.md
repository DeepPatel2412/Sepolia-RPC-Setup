# 🔗 Sepolia RPC Setup (By Creed)

Deploy and manage an Ethereum Sepolia RPC node on your VPS in seconds with a single command. This solution uses Dockerized **Reth**, **Prysm**, **HAProxy**, and **Dozzle** for a secure, production-ready testnet setup. Cleanup is just as easy—reset or remove everything with one command.

------------------------------------------
## Minimum Requirements:
Ubuntu 22.04+ recommended
- 4 CPU Cores
- 8GB RAM
- 1TB+ SSD
- Root or sudo access

------------------------------------------

## Reccomended Requirements:
Ubuntu 22.04+ recommended
- 6+ CPU Cores
- 16GB+ RAM
- 1TB+ SSD
- Root or sudo access

------------------------------------------

## 🚀 Quick Start & Management Guide
### Initial sync will take upto 8-12 Hrs 
- depending on your SSD/Network Speed and other specs,Until than you won't be able to use the rpc after setup.

## ✅ Start Screen:**
```
screen -S rpc
```

## ✅ To install, run:**
```
bash <(curl -Ls https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/setup-sepolia.sh)
```

## ✅ End Screen: (Only after the whole setup is complete)**
```
screen -XS rpc quit
```

## 🔍 Monitor rpc logs once the setup is complete (Run in any browser)
```
http://your-RPC-IP:9999/
```
Replace your VPS ip and run open it in browser. 

------------------------------------------
## ✔️ Endpoints after setup (use localhost if same vps - use vpsIP if seperate vps )
- **Reth (RPC):** `http://<localhost/YOUR_SERVER_IP>:8545` 
- **Prysm (Beacon):** `http://<localhost/YOUR_SERVER_IP>:3500`
- **Dozzle Monitoring:** `http://<YOUR_SERVER_IP>:9999` (Open In Browser To Monitor Node Logs)
  
------------------------------------------
## 💭 What happens when you run the setup command?
- Checks your VPS for required CPU, RAM, and disk space.
- Installs Docker & Docker Compose if missing.
- Creates the `Ethereum` data directory.
- Download snapshot
- Generates a JWT secret and sets up an IP whitelist for secure RPC access.
- Downloads and configures Docker Compose for Reth, Prysm, and Dozzle.
- Configures your firewall to only allow necessary ports.
- Starts all services in Docker containers.
- Prints your RPC, Beacon, and monitoring URLs.
  
------------------------------------------
## 📂 Directory Structure (For info only do not run this)
After setup, your directory tree will look like this:
```
Ethereum/
├── Execution/
├── Consensus/
├── docker-compose.yml
├── haproxy.cfg
├── jwt.hex
└── whitelist.lst
```

------------------------------------------
## 📍 Add IPs to your Whitelist (Run)
- Exacmple : 12.1203.09 when asked to enter IP
```
bash <(curl -Ls https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/ufwWhitelistTool)
```

------------------------------------------
## ⚠️ Security Tips
- Only whitelist trusted IPs for RPC access.
- Keep your JWT secret safe (auto-generated).
- Regularly update your server and Docker images.

------------------------------------------
## ❌ To clean up/Delete (Run)
```
bash <(curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/sepolia-RPC-cleanup)
```
This will be the options available to choose from :
- Reth
- Prysm
- HAproxy (yet to be implemented)
- Dozzle
- All
------------------------------------------
## 💭 What happens when you run the cleanup command?
- Lets you choose which components to remove (Reth, Prysm, HAProxy, Dozzle, or all).
- Stops and deletes the selected Docker containers and images.
- Optionally removes the Ethereum data directory and related config files.
- Frees up disk space and resets your environment for a fresh start.
  
------------------------------------------
------------------------------------------
## Need help?
- Open an [issue](https://github.com/DeepPatel2412/Sepolia-RPC-Setup/issues) on the repo.
- Or reach out on Discord: [creed2412](https://discordapp.com/users/517654585956106261)
  
------------------------------------------
------------------------------------------
# Happy Node Running! 🚀
