# Awning

A fully dockerized Bitcoin + Lightning node. Something like [Umbrel](https://umbrel.com) but lighter and portable. Something like [RaspiBolt](https://raspibolt.org/) but easier and automated. Bitcoin/Lightning-Network oriented with no frills.

**Awning** doesn't install anything on your host besides Docker, making it lightweight, customizable and portable.

## Disclaimer

This open-source project is provided 'as-is' without any warranty of any kind, either expressed or implied. The developers are not liable for any damages or losses arising out of the use of this software.

Please read the [full disclaimer](DISCLAIMER.md) before using this project.

## What's included

| Service | Description |
| --- | --- |
| [Bitcoin Core](https://github.com/bitcoin/bitcoin) | Full Bitcoin node with GPG-verified download |
| [LND](https://github.com/lightningnetwork/lnd) | Lightning Network Daemon |
| [Electrs](https://github.com/romanz/electrs) | Electrum Rust Server (compiled from source) |
| [Tor](https://www.torproject.org/) | SOCKS proxy + hidden services |
| [Nginx](https://github.com/nginx) | SSL termination for Electrs |
| [SCB](https://github.com/lightningnetwork/lnd/blob/master/docs/recovery.md) | Automatic Static Channel Backup to GitHub |

## Prerequisites

- Docker with the [compose plugin](https://docs.docker.com/compose/install/linux/)

```sh
sudo apt-get install -y docker.io docker-compose-v2
```

> **Note:** No other host dependencies are required. The setup wizard runs helper tooling in Docker containers (including Python-based steps), so Python is not required on the host.

## Quick start

```sh
git clone https://github.com/giovantenne/awning.git
cd awning
./awning.sh
```

The setup wizard will guide you through:
1. Prerequisites check
2. Node configuration (architecture auto-detected, versions)
3. Static Channel Backup configuration (GitHub SSH repository)
4. Config generation (RPC auth, Tor passwords, all handled automatically)
5. Build and start all services
6. LND wallet initialization (auto-unlock password + wallet create)

After setup, run `./awning.sh` again to open the interactive management menu.

## Usage

```
./awning.sh [command]

Commands:
  (none)          Interactive menu (or setup wizard on first run)
  setup           Run the setup wizard

  start           Start all services
  stop            Stop all services
  restart [svc]   Restart services (optionally specify which)
  build [svc]     Build Docker images
  update          Rebuild and restart all services

  status          Show service status and sync progress
  logs [svc]      Follow service logs
  connections     Show wallet connection info

  wallet-create   Create LND wallet (first time)
  wallet-unlock   Manually unlock LND wallet
  zeus-connect    Generate Zeus wallet connection URI

  bitcoin-cli     Run bitcoin-cli commands
  lncli           Run lncli commands

  help            Show help
```

## Network ports

| Port | Service | Description |
| --- | --- | --- |
| `8080` | LND | REST API (TLS, configurable via `LND_REST_PORT`) |
| `50002` | Electrs via Nginx | Electrum protocol (SSL, configurable via `ELECTRS_SSL_PORT`) |

By default, both ports bind to `127.0.0.1` for safer local-only access. Set `LND_REST_BIND=0.0.0.0` and/or `ELECTRS_SSL_BIND=0.0.0.0` in `.env` for LAN exposure.
Both services are also available as Tor hidden services (`.onion` addresses shown in `./awning.sh connections`).

## Connect your wallet

### Electrs (Sparrow, Blue Wallet, etc.)

Get your Electrs connection info:
```sh
./awning.sh connections
```

Use the local IP address with port `50002` (SSL) or the `.onion` address with port `50001` via Tor.

### Zeus (via Tor)

```sh
./awning.sh zeus-connect
```

This generates an lndconnect URI for Zeus. In Zeus: Add Node > lndconnect REST.

## Updating versions

Edit `.env` to change `BITCOIN_CORE_VERSION`, `LND_VERSION`, or `ELECTRS_VERSION`, then:

```sh
./awning.sh update
```

## Directory structure

```
awning/
├── awning.sh                    # Main entry point
├── lib/
│   ├── common.sh                # Logging, colors, utilities
│   ├── docker.sh                # Docker compose wrappers
│   ├── setup.sh                 # Setup wizard
│   ├── health.sh                # Status checks
│   └── menu.sh                  # Interactive menu
├── configs/
│   ├── bitcoin.conf.template    # Bitcoin Core config template
│   ├── lnd.conf.template        # LND config template
│   ├── electrs.toml.template    # Electrs config template
│   └── torrc.template           # Tor config template
├── data/
│   ├── bitcoin/                 # Blockchain data
│   ├── lnd/                     # LND data + wallet
│   ├── electrs/                 # Electrs index
│   ├── tor/                     # Tor hidden service keys
│   └── scb/                     # SCB git repo
├── dockerfiles/
│   ├── Dockerfile.bitcoin
│   ├── Dockerfile.lnd
│   ├── Dockerfile.electrs
│   ├── Dockerfile.tor
│   ├── Dockerfile.nginx
│   ├── Dockerfile.scb
│   ├── entrypoints/
│   │   ├── lnd.sh
│   │   └── scb.sh
│   └── files/
│       └── nginx.conf
├── docker-compose.yml
├── .env.sample
└── README.md
```

## Security

- **RPC authentication**: Bitcoin Core uses `rpcauth` (HMAC-SHA256 hashed password) instead of cookie files. Credentials are auto-generated during setup.
- **Tor control auth**: Uses hashed password instead of shared cookie file.
- **Network isolation**: Services run on isolated Docker bridge networks. Tor is on a dedicated network shared only with services that need it (`bitcoin`, `lnd`, `electrs`). Only LND REST (8080) and Electrs SSL (50002) are exposed to the host.
- **Tor by default**: Bitcoin Core connects to peers via Tor (`proxy=tor:9050`).
- **GPG verification**: Bitcoin Core and LND binaries are GPG-verified during Docker build.

## Support

For any questions or issues you can join our [Telegram support channel](https://t.me/awning_node) or open a [GitHub issue](https://github.com/giovantenne/awning/issues/new).

## Donations

If you would like to contribute and help dev team with this project you can send a donation to the following LN address `cg@pos.btcpayserver.it` or on-chain `bc1qdx6r7z2c2dtdfa2tn9a2u4rc3g5myyfquqq97x`
