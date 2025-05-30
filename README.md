# 🔗 Sepolia RPC Setup (By Creed)

Deploy and manage an Ethereum Sepolia RPC node on your VPS in seconds with a single command. This solution uses Dockerized **Reth**, **Prysm**, **HAProxy**, and **Dozzle** for a secure, production-ready testnet setup. Cleanup is just as easy—reset or remove everything with one command.

------------------------------------------
** Minimum Requirements:**
- Ubuntu 22.04+ recommended
- 4+ CPU cores, 8GB+ RAM, 750GB+ SSD
- Root or sudo access
------------------------------------------

## 🚀 Quick Start & Management Guide

**To install, run:**
```
bash <(curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/sepolia-RPC-setup)
```
------------------------------------------
**To clean up, run:**
```
bash <(curl -fsSL https://raw.githubusercontent.com/DeepPatel2412/Sepolia-RPC-Setup/main/sepolia-RPC-cleanup)
```
------------------------------------------
**What happens when you run the setup command?**
- Checks your VPS for required CPU, RAM, and disk space.
- Installs Docker & Docker Compose if missing.
- Creates the `Ethereum` data directory.
- Generates a JWT secret and sets up an IP whitelist for secure RPC access.
- Downloads and configures Docker Compose for Reth, Prysm, HAProxy, and Dozzle.
- Configures your firewall to only allow necessary ports.
- Starts all services in Docker containers.
- Prints your RPC, Beacon, and monitoring URLs.
------------------------------------------
## 📂 Directory Structure
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
**Endpoints after setup:**
- **Reth (RPC):** `http://<YOUR_SERVER_IP>/reth/`
- **Prysm (Beacon):** `http://<YOUR_SERVER_IP>/prysm/`
- **Dozzle Monitoring:** `http://<YOUR_SERVER_IP>:9999`
------------------------------------------
## 📍 Add IPs to your Whitelist (Run)
```
cd Ethereum
echo "YOUR_IP/CIDR" >> whitelist.lst
sudo docker restart haproxy
cd
```
------------------------------------------
**Security Tips:**
- Only whitelist trusted IPs for RPC access.
- Keep your JWT secret safe (auto-generated).
- Regularly update your server and Docker images.
------------------------------------------
**What happens when you run the cleanup command?**
- Lets you choose which components to remove (Reth, Prysm, HAProxy, Dozzle, or all).
- Stops and deletes the selected Docker containers and images.
- Optionally removes the Ethereum data directory and related config files.
- Frees up disk space and resets your environment for a fresh start.
------------------------------------------
------------------------------------------
**Need help?**  
- Open an [issue](https://github.com/DeepPatel2412/Sepolia-RPC-Setup/issues) on the repo.
- Or reach out on Discord: [creed2412](https://discordapp.com/users/517654585956106261)
---

Happy Node Running! 🚀
