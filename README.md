# <img src="https://awning.dev/awning.png" alt="Awning" width="50" height="50" align="absmiddle" /> Awning

[![Language](https://img.shields.io/badge/Language-Bash-121011.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/) [![Runtime](https://img.shields.io/badge/Runtime-Docker-2496ED.svg?logo=docker&logoColor=white)](https://www.docker.com/) [![Network](https://img.shields.io/badge/Network-Tor-7D4698.svg?logo=torproject&logoColor=white)](https://www.torproject.org/) [![Bitcoin](https://img.shields.io/badge/Bitcoin-Core-F7931A.svg?logo=bitcoin&logoColor=white)](https://github.com/bitcoin/bitcoin) [![Lightning](https://img.shields.io/badge/Lightning-LND-1E90FF.svg)](https://github.com/lightningnetwork/lnd) [![License](https://img.shields.io/github/license/giovantenne/awning.svg)](LICENSE)



A portable, TUI-first Bitcoin + Lightning node stack.

Only requires Docker. No Python, Node.js, Go, or other runtimes. One directory, one command, one dependency.

Website: [awning.dev](https://awning.dev)

## 🚀 Quick Start

```sh
git clone https://github.com/giovantenne/awning.git
cd awning
./awning.sh
```

On first run, Awning auto-detects your system, fetches the latest software versions, and walks you through setup. Press **Enter** to accept defaults, or type **`w`** for the advanced wizard.

After setup completes, **write down the 24-word recovery seed** — it is shown only once.



<div align="center">
  <video src="https://github.com/user-attachments/assets/368aa903-d42a-4874-b6d3-39d3762e70a0" autoplay muted loop playsinline controls></video>
</div>




## 💡 Why Awning

- **Single dependency.** Only Docker is required on the host. Nothing else to install or maintain.
- **Portable.** The entire stack lives in one directory. Copy it to an external drive or another machine — no reinstallation needed (see [Portability](#portability)).
- **Lightweight.** No web server, no Electron app, no background daemon. Awning is a terminal tool that starts when you need it and gets out of the way.
- **Secure defaults.** Services bind to localhost, credentials are auto-generated with strong entropy, files are permission-restricted, containers run with dropped capabilities, and all Bitcoin traffic routes through Tor.
- **Transparent.** The entire codebase is readable shell scripts and Docker Compose. No build step, no compiled binaries, no hidden abstractions.

## 📦 What's Included

| Service | Purpose |
| --- | --- |
| [Bitcoin Core](https://github.com/bitcoin/bitcoin) | Full node (RPC backend) |
| [LND](https://github.com/lightningnetwork/lnd) | Lightning Network daemon |
| [Electrs](https://github.com/romanz/electrs) | Electrum server (Rust) |
| [Tor](https://www.torproject.org/) | SOCKS proxy + hidden services |
| [RTL](https://github.com/Ride-The-Lightning/RTL) | Web UI for LND (optional, LAN-accessible) |
| SCB watcher | Auto-backup of channel state to a Git repository |

## 🔧 Prerequisites

- **Docker Engine** (20.10+) with **Compose plugin** (`docker compose`)
- **~900 GB** free disk space (blockchain + indexes)
- **8 GB RAM** recommended (resource limits are tuned for Raspberry Pi 5 8GB)
- Linux x86_64 or aarch64 (ARM64)

Example (Debian/Ubuntu):
```sh
sudo apt-get install -y docker.io docker-compose-v2 git
```

> **Note:** Initial Bitcoin sync takes several days. Electrs indexing adds more time. Building Electrs from source can take up to 1 hour on ARM.

## 💻 Commands

```
./awning.sh                 Interactive menu (or auto-setup on first run)
./awning.sh setup           Run the setup wizard
./awning.sh start|stop      Start or stop all services
./awning.sh restart [svc]   Restart all or selected services
./awning.sh rebuild         Rebuild and restart all services
./awning.sh status          Dashboard with sync progress
./awning.sh logs [svc]      Follow service logs
./awning.sh connections     Tor addresses, LND connect URIs
./awning.sh zeus-connect    Generate Zeus wallet connection
./awning.sh bitcoin-cli     Run bitcoin-cli commands
./awning.sh lncli           Run lncli commands
```

Rerunning `./awning.sh setup` keeps your existing values as defaults. Use `--ignore-disk-space` to skip the disk check.

## 🔌 Wallet Connections

**Electrum-compatible wallets:**
```sh
./awning.sh connections
```

By default, Electrs binds to `127.0.0.1` (local only). To expose it on your LAN, edit `.env` and set `ELECTRS_SSL_BIND=0.0.0.0`, then restart. Alternatively, use the Tor endpoint (`.onion:50001`) which is always reachable.

**Zeus:**
```sh
./awning.sh zeus-connect
```
In Zeus: *Add Node > lndconnect REST*.

**RTL (Web UI):**
- RTL is exposed on port `3001` over HTTPS.
- Open `https://<HOST_IP>:3001`.
- Because RTL uses a self-signed certificate, your browser will show a warning: click **Advanced > Proceed**.

## 💾 SCB (Static Channel Backup)

SCB automatically backs up your Lightning channel state to a private GitHub repository. Disabled by default.

To enable: run `./awning.sh setup` or use *Menu > Tools > Setup wizard*. You need:
- A private GitHub repository
- An SSH deploy key with write access (the wizard generates one)

The wizard tests push access before completing. Manual backups: *Menu > Backup > Trigger backup now*.

## 🛰️ Network Ports

Services bind to localhost by default (except RTL which is LAN-accessible).

| Port | Service | Default Bind | Description |
| --- | --- | --- | --- |
| `8080` | LND REST | `127.0.0.1` | TLS REST API |
| `50002` | Electrs (via stunnel) | `127.0.0.1` | Electrum SSL |
| `3001` | RTL | `0.0.0.0` | Web interface (HTTPS, password protected) |

Configurable in `.env` via `*_BIND` and `*_PORT` variables. Both LND and Electrs are also reachable through Tor hidden services.
For RTL on `3001`, browsers will warn about the self-signed certificate on first access: use **Advanced > Proceed**.

## ⚙️ Configuration

All configuration lives in `.env` (generated by setup). See [`.env.sample`](.env.sample) for a documented template.

| Variable | Source | Description |
| --- | --- | --- |
| `HOST_UID` / `HOST_GID` | Auto-detected | Container file ownership |
| `BITCOIN_ARCH` / `LND_ARCH` | Auto-detected | CPU architecture for binary downloads |
| `BITCOIN_CORE_VERSION` | Setup | Bitcoin Core version |
| `LND_VERSION` | Setup | LND version |
| `ELECTRS_VERSION` | Setup | Electrs version |
| `RTL_VERSION` | Setup | RTL version |
| `NODE_ALIAS` | Setup | Lightning node alias (max 32 chars) |
| `LND_REST_BIND` / `LND_REST_PORT` | Setup | LND REST bind and port |
| `ELECTRS_SSL_BIND` / `ELECTRS_SSL_PORT` | Setup | Electrs SSL bind and port |
| `RTL_BIND` / `RTL_PORT` | Setup | RTL bind and port |
| `BITCOIN_RPC_USER` / `BITCOIN_RPC_PASSWORD` | Generated | Bitcoin RPC credentials |
| `TOR_CONTROL_PASSWORD` | Generated | Tor control port password |
| `RTL_PASSWORD` | Setup | RTL web UI password |
| `SCB_REPO` | Setup | Git SSH URL for channel backup |
| `BITCOIN_MEM_LIMIT` / `BITCOIN_CPUS` | Optional | Bitcoin Core resource limits (default: 4g / 2.0) |
| `LND_MEM_LIMIT` / `LND_CPUS` | Optional | LND resource limits (default: 512m / 0.5) |
| `ELECTRS_MEM_LIMIT` / `ELECTRS_CPUS` | Optional | Electrs resource limits (default: 2g / 1.0) |

### Advanced Config Overrides (`.user.conf`)

Generated service configs are rebuilt by setup. For persistent custom overrides, use files in `configs/user/`:

- `configs/user/bitcoin.user.conf` (appended to `configs/bitcoin.conf`)
- `configs/user/lnd.user.conf` (appended to `configs/lnd.conf`)
- `configs/user/electrs.user.conf` (appended to `configs/electrs.toml`)
- `configs/user/torrc.user.conf` (appended to `configs/torrc`)
- `configs/user/rtl.user.conf` (full replacement for `configs/rtl.conf`)

**Warning:** `.user.conf` overrides are loaded as-is. Invalid or conflicting options can prevent services from starting and may lead to data loss or fund loss.

To upgrade versions: edit `.env`, then run `./awning.sh rebuild`.

## 🧳 Portability

Awning is designed to be portable. All state — blockchain data, wallet, configs — lives under the `awning/` directory.

To move your node to another machine or external drive:

```sh
# On the source machine
./awning.sh stop
cp -a awning/ /mnt/external/awning/

# On the target machine
cd /mnt/external/awning
./awning.sh start
```

The only requirement on the target machine is Docker.

## 📁 Project Layout

```
awning/
├── awning.sh              # Entry point (CLI + TUI)
├── docker-compose.yml
├── .env                   # Generated config (gitignored)
├── configs/
│   ├── templates/         # Setup-managed config templates
│   ├── user/              # Optional local .user.conf overrides
│   ├── *.conf             # Generated runtime configs (setup output)
│   └── *.toml / torrc     # Generated runtime configs (setup output)
├── data/                  # Persistent runtime data (gitignored)
│   ├── bitcoin/           # Blockchain, chainstate, indexes
│   ├── lnd/               # Wallet, TLS certs, macaroons, channels
│   ├── electrs/           # Electrum index
│   ├── tor/               # Hidden service keys
│   ├── scb/               # SSH keys and backup repo
│   └── rtl/               # RTL runtime config
├── dockerfiles/           # Dockerfile per service + entrypoints
├── docs/                  # Documentation assets (README GIFs, images)
├── lib/                   # Shell modules
│   ├── common.sh          # UI, colors, logging, input, validation
│   ├── docker.sh          # Docker Compose wrappers
│   ├── setup.sh           # Setup wizard + auto-setup
│   ├── health.sh          # Status dashboard, sync progress
│   └── menu.sh            # Interactive TUI menus
└── tests/                 # Unit tests (bats-core)
```

## 🔒 Security

**Network isolation.** Services communicate through Docker bridge networks. Bitcoin and LND route all P2P traffic through Tor.

**Credentials.** RPC passwords, Tor control passwords, and RTL passwords are auto-generated with high entropy from `/dev/urandom`. Sensitive files (`.env`, `password.txt`) are `chmod 600`.

**Binary verification.** Bitcoin Core and LND binaries are GPG-verified during Docker build. The lndconnect binary is SHA256-verified.

**Container hardening.** All containers run with `cap_drop: ALL`, `no-new-privileges`, and enforced memory/CPU limits. Log rotation prevents disk exhaustion.

**Concurrent execution.** A lock file prevents multiple instances of `awning.sh` from running simultaneously, protecting against config corruption.

**Configuration validation.** `.env` values are validated at startup — invalid ports, architectures, or UIDs are caught before reaching Docker.

## 🔄 Upgrading From v1

Run setup on v2:
```sh
./awning.sh setup
```
Existing blockchain data, wallet, and channel state are preserved.

## 🧪 Testing

```sh
bats tests/unit.bats
```

Requires [bats-core](https://github.com/bats-core/bats-core). Install: `npm install -g bats` or via your package manager.

## ⚠️ Disclaimer

This open-source project is provided "as is" without warranty of any kind. The developers are not liable for damages or losses resulting from usage.

Read the full disclaimer before use: [DISCLAIMER.md](DISCLAIMER.md)

## 🛟 Support

Issues: https://github.com/giovantenne/awning/issues/new

## ❤️ Donations

- Lightning: `cg@pos.btcpayserver.it`
- On-chain: `bc1qdx6r7z2c2dtdfa2tn9a2u4rc3g5myyfquqq97x`
