# User Overrides (.user.conf)

Files in this directory are optional local overrides loaded during setup.

- `bitcoin.user.conf` -> appended to `configs/bitcoin.conf`
- `lnd.user.conf` -> appended to `configs/lnd.conf`
- `electrs.user.conf` -> appended to `configs/electrs.toml`
- `torrc.user.conf` -> appended to `configs/torrc`
- `rtl.user.conf` -> full replacement for `configs/rtl.conf`

WARNING: invalid or conflicting settings can prevent services from starting and may cause data loss or fund loss.
