# Awning

A portable, TUI-first Bitcoin + Lightning node stack.

Awning delivers a no-frills Bitcoin/Lightning stack focused on Bitcoin Core, LND, Electrs, Tor, and automatic static channel backups (SCB). The only host dependency is Docker (+ compose plugin).

## Disclaimer

This open-source project is provided "as is" without warranty of any kind.
The developers are not liable for damages or losses resulting from usage.

Read the full disclaimer before use: [DISCLAIMER.md](DISCLAIMER.md)

## What Is Included

| Service | Purpose |
| --- | --- |
| [Bitcoin Core](https://github.com/bitcoin/bitcoin) | Full node, RPC + ZMQ backend |
| [LND](https://github.com/lightningnetwork/lnd) | Lightning node |
| [Electrs](https://github.com/romanz/electrs) | Electrum server (Rust implementation) |
| [Tor](https://www.torproject.org/) | SOCKS proxy + hidden services |
| [Nginx](https://github.com/nginx) | SSL termination for Electrs |
| [RTL](https://github.com/Ride-The-Lightning/RTL) | Web UI for LND |
| [SCB watcher](https://github.com/lightningnetwork/lnd/blob/master/docs/recovery.md) | Auto backup of `channel.backup` to Git repository |

## Prerequisites

- **Docker Engine** (20.10+)
- **Docker Compose** plugin (`docker compose`) or standalone `docker-compose`
- **~900 GB** of free disk space (Bitcoin blockchain + indexes)
- `git` (recommended for cloning)

**Supported platforms:** Linux x86_64, Linux aarch64 (ARM64).

Example (Debian/Ubuntu):

```sh
sudo apt-get install -y docker.io docker-compose-v2 git
```

> **Note:** The initial Bitcoin blockchain download takes several days. Electrs indexing adds additional time. Building Electrs from source can take up to 1 hour on ARM.

## Quick Start

```sh
git clone https://github.com/giovantenne/awning.git
cd awning
./awning.sh
```

On first run, Awning starts an automatic setup that:

1. Checks prerequisites (Docker, disk space, connectivity)
2. Detects your system architecture and UID/GID
3. Fetches the latest software versions from GitHub
4. Shows a configuration summary with sensible defaults
5. Asks for an **RTL password** (the only interactive prompt)
6. Offers a choice: **Enter** to proceed, or **'w'** for the advanced setup wizard
7. Generates configs and credentials
8. Builds Docker images (7 services)
9. Starts all services
10. Creates the LND wallet automatically
11. Displays the **24-word recovery seed** -- write it down!

After setup, Awning opens the interactive management menu.

### Advanced Setup Wizard

If you need to customize versions, node alias, SCB, or other settings, type **'w'** at the auto-setup prompt to launch the full interactive wizard. The wizard is also accessible later from **Menu > Tools > Setup wizard**.

## Run Setup Again

```sh
./awning.sh setup
```

Useful options:
- `./awning.sh setup --ignore-disk-space` (or `--force`)

Rerunning setup keeps previously configured values as defaults.

## Upgrading From v1

If you are coming from Awning v1, run setup again on v2:

```sh
./awning.sh setup
```

This regenerates v2 configs and validates existing values. Your existing blockchain data, wallet, and channel state are preserved.

## Commands

```text
./awning.sh [command]

Commands:
  (none)            Interactive menu (or auto-setup on first run)
  setup             Run the setup wizard
  help              Show help

Services:
  start             Start all services
  stop              Stop all services
  restart [svc]     Restart all or selected services
  build [svc]       Build images (all or selected)
  update            Rebuild and restart all services

Monitoring:
  status            Service status + sync overview
  logs [svc]        Follow logs
  connections       Connection details (local + Tor)

Wallet:
  wallet-balance    Show LND on-chain balance
  channel-balance   Show LND Lightning balance
  new-address       Generate a new on-chain address
  zeus-connect      Print lndconnect URI for Zeus wallet

CLI:
  bitcoin-cli       Run bitcoin-cli commands
  lncli             Run lncli commands
```

## SCB (Static Channel Backup)

SCB is disabled by default. To enable it, run the setup wizard:

```sh
./awning.sh setup
```

Or use **Menu > Tools > Setup wizard**.

You will need:
- A private GitHub repository
- An SSH deploy key with write access

The wizard will:
- Generate a deploy key (`data/scb/.ssh/id_ed25519.pub`)
- Test push permission (dry-run)
- Configure the SCB watcher service

Menu operations:
- `Backup -> Trigger backup now`
- `Backup -> View SCB logs`

## Network Ports

By default, services bind to localhost for safety (except RTL which binds to `0.0.0.0` for LAN access).

| Port | Service | Default Bind | Description |
| --- | --- | --- | --- |
| `8080` | LND REST | `127.0.0.1` | TLS REST API |
| `50002` | Electrs (via Nginx) | `127.0.0.1` | Electrum SSL |
| `3000` | RTL | `0.0.0.0` | Web interface (password protected) |

Binding controls in `.env`:
- `LND_REST_BIND`, `LND_REST_PORT`
- `ELECTRS_SSL_BIND`, `ELECTRS_SSL_PORT`
- `RTL_BIND`, `RTL_PORT`

Both LND and Electrs are also exposed through Tor hidden services.

## Wallet Connections

### Electrum-compatible wallets

Run:
```sh
./awning.sh connections
```

By default, the Electrs SSL port (`50002`) is bound to `127.0.0.1` and only reachable from the node itself. To connect from another device on your LAN, stop the services, change the bind address in `.env`, and restart:

```sh
./awning.sh stop
# Edit .env: change ELECTRS_SSL_BIND=127.0.0.1 to ELECTRS_SSL_BIND=0.0.0.0
./awning.sh start
```

Alternatively, use the **Tor endpoint** (`.onion:50001`) which is always reachable without changing the bind address.

### Zeus

Run:
```sh
./awning.sh zeus-connect
```

In Zeus: `Add Node -> lndconnect REST`.

## Configuration Reference

All configuration is managed through `.env` (generated by setup). See [`.env.sample`](.env.sample) for a documented template.

| Variable | Auto | Description |
| --- | --- | --- |
| `HOST_UID` / `HOST_GID` | Yes | Host user/group IDs for container file ownership |
| `BITCOIN_ARCH` / `LND_ARCH` | Yes | CPU architecture for binary downloads |
| `BITCOIN_CORE_VERSION` | Setup | Bitcoin Core release version |
| `LND_VERSION` | Setup | LND release version |
| `ELECTRS_VERSION` | Setup | Electrs release version |
| `RTL_VERSION` | Setup | RTL release version |
| `NODE_ALIAS` | Setup | Lightning node alias (A-Z a-z 0-9 . _ - max 32) |
| `LND_REST_BIND` / `LND_REST_PORT` | Setup | LND REST API bind address and port |
| `ELECTRS_SSL_BIND` / `ELECTRS_SSL_PORT` | Setup | Electrs SSL bind address and port |
| `RTL_BIND` / `RTL_PORT` | Setup | RTL web interface bind address and port |
| `BITCOIN_RPC_USER` / `BITCOIN_RPC_PASSWORD` | Generated | Bitcoin RPC credentials |
| `TOR_CONTROL_PASSWORD` | Generated | Tor control port password |
| `RTL_PASSWORD` | Setup | RTL web UI password |
| `SCB_REPO` | Setup | Git SSH URL for channel backup repo |

To update versions: edit `.env`, then run `./awning.sh update`.

## Data and Project Layout

```text
awning/
├── awning.sh              # Main entry point (CLI + TUI)
├── docker-compose.yml
├── .env.sample
├── configs/               # Service config templates and generated configs
├── data/                  # Persistent runtime data (gitignored)
├── dockerfiles/
│   ├── Dockerfile.*       # One per service
│   └── entrypoints/       # Container startup scripts
├── lib/
│   ├── common.sh          # UI primitives, colors, logging, input
│   ├── docker.sh          # Docker compose wrappers
│   ├── setup.sh           # Setup wizard + auto-setup
│   ├── health.sh          # Status dashboard, sync progress
│   └── menu.sh            # Interactive TUI menus
└── README.md
```

Persistent state lives in `data/`:
- `data/bitcoin` - Blockchain, chainstate, indexes
- `data/lnd` - Wallet, TLS certs, macaroons, channel state
- `data/electrs` - Electrum index database
- `data/tor` - Hidden service keys
- `data/scb` - SSH keys and backup repo clone

## Security Notes

- Docker network isolation is used between services.
- Bitcoin RPC auth uses `rpcauth` in `bitcoin.conf`.
- Tor control uses hashed password.
- Sensitive generated files (`.env`, `password.txt`) are permission-restricted (`chmod 600`).
- All Bitcoin P2P traffic is routed through Tor by default.
- Binary downloads (Bitcoin Core, LND) are GPG-verified during build.
- RTL is exposed on LAN by default but protected by the RTL password.

## Support

- Issues: https://github.com/giovantenne/awning/issues/new

## Donations

- Lightning: `cg@pos.btcpayserver.it`
- On-chain: `bc1qdx6r7z2c2dtdfa2tn9a2u4rc3g5myyfquqq97x`
