# Awning

A fully dockerized Bitcoin + Lightning node.

Awning is designed to be simple to run, easy to inspect, and portable across hosts. It aims for a no-frills setup focused on Bitcoin Core, LND, Electrs, Tor, and automatic static channel backups (SCB).

Awning keeps host dependencies minimal: Docker (+ compose plugin) is enough.

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
| [SCB watcher](https://github.com/lightningnetwork/lnd/blob/master/docs/recovery.md) | Auto backup of `channel.backup` to Git repository |

## Prerequisites

- Docker Engine
- Docker Compose plugin (`docker compose`)
- `git` (recommended for cloning)

Example (Debian/Ubuntu):

```sh
sudo apt-get install -y docker.io docker-compose-v2 git
```

## Quick Start (Recommended)

```sh
git clone https://github.com/giovantenne/awning.git
cd awning
./awning.sh
```

On first run, the setup wizard starts automatically.

The wizard will:
1. Check prerequisites
2. Configure node parameters (alias, versions, architecture)
3. Optionally configure SCB repository + deploy key test
4. Generate configs and credentials
5. Build and start services
6. Initialize LND wallet

After setup, Awning opens the main menu automatically.

## Run Setup Again

```sh
./awning.sh setup
```

Useful options:
- `./awning.sh setup --ignore-disk-space` (or `--force`)

Rerunning setup keeps previously configured values as defaults (alias, versions, SCB repo, credentials) to avoid re-entering everything.

## Main Commands

```text
./awning.sh [command]

Commands:
  (none)          Interactive menu
  setup           Run setup wizard

Services:
  start           Start all services
  stop            Stop all services
  restart [svc]   Restart all or selected services
  build [svc]     Build images (all or selected)
  update          Rebuild and restart all services

Monitoring:
  status          Service status + sync overview
  logs [svc]      Follow logs
  connections     Connection details (local + Tor)

Wallet:
  wallet-create   Create LND wallet
  wallet-unlock   Manual wallet unlock (fallback)
  zeus-connect    Print lndconnect URI

CLI:
  bitcoin-cli     Run bitcoin-cli
  lncli           Run lncli
```

## SCB (Static Channel Backup)

If enabled, Awning monitors LND `channel.backup` and pushes updates to your Git repo.

With setup wizard:
- You provide SSH repo URL (for example `git@github.com:owner/repo.git`)
- Awning generates deploy key (`data/scb/.ssh/id_ed25519.pub`)
- You add it to repository deploy keys with write access
- Wizard tests push permission (dry-run)

Menu:
- `Backup -> Trigger backup now`
- `Backup -> View SCB logs`

## Network Ports

By default, services bind to localhost for safety.

| Port | Service | Description |
| --- | --- | --- |
| `8080` | LND REST | TLS REST API |
| `50002` | Electrs (via Nginx) | Electrum SSL |

Binding controls in `.env`:
- `LND_REST_BIND`, `LND_REST_PORT`
- `ELECTRS_SSL_BIND`, `ELECTRS_SSL_PORT`

Both LND and Electrs are also exposed through Tor hidden services.

## Wallet Connections

### Electrum-compatible wallets

Run:
```sh
./awning.sh connections
```

Use:
- local endpoint (`<host>:50002` SSL), or
- Tor endpoint (`.onion:50001`).

### Zeus

Run:
```sh
./awning.sh zeus-connect
```

In Zeus: `Add Node -> lndconnect REST`.

## Version Management

You can update service versions from setup, or editing `.env`:
- `BITCOIN_CORE_VERSION`
- `LND_VERSION`
- `ELECTRS_VERSION`

Then rebuild:

```sh
./awning.sh update
```

## Data and Project Layout

```text
awning/
├── awning.sh
├── docker-compose.yml
├── .env.sample
├── configs/
├── data/
├── dockerfiles/
│   ├── Dockerfile.bitcoin
│   ├── Dockerfile.lnd
│   ├── Dockerfile.electrs
│   ├── Dockerfile.tor
│   ├── Dockerfile.nginx
│   ├── Dockerfile.scb
│   └── entrypoints/
├── lib/
│   ├── common.sh
│   ├── docker.sh
│   ├── setup.sh
│   ├── health.sh
│   └── menu.sh
└── README.md
```

Persistent state lives in `data/`:
- `data/bitcoin`
- `data/lnd`
- `data/electrs`
- `data/tor`
- `data/scb`

## Troubleshooting

### LND restarting

Check logs:
```sh
./awning.sh logs lnd
```

Common causes:
- wallet not initialized
- RPC credential mismatch after manual config edits
- Tor/controller auth mismatch

Use setup rerun to regenerate/reconcile configs:
```sh
./awning.sh setup
```

### Service health

Use:
```sh
./awning.sh status
```

State meanings:
- `healthy`: container + healthcheck OK
- `running`: container running (no healthcheck)
- `starting/restarting/unhealthy`: investigate with logs

## Security Notes

- Docker network isolation is used between services.
- Bitcoin RPC auth uses `rpcauth` in `bitcoin.conf`.
- Tor control uses hashed password.
- Sensitive generated files (`.env`, passwords) are permission-restricted.

## Support

- Issues: https://github.com/giovantenne/awning/issues/new

## Donations

- Lightning: `cg@pos.btcpayserver.it`
- On-chain: `bc1qdx6r7z2c2dtdfa2tn9a2u4rc3g5myyfquqq97x`
