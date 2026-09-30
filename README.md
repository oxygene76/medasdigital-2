# MedasDigital 2.0

MedasDigital 2.0 is a blockchain built on the Cosmos SDK for creating and
owning digital assets. It supports:
- custom tokens (token factory),
- NFTs,
- CosmWasm smart contracts,
- IBC.

The network is secured by CometBFT consensus and governed on-chain by its
token holders.

This repository contains the chain software (`medasdigitald`), the mainnet
genesis and the operator tooling.

## Network

| | |
|---|---|
| Chain ID | `medasdigital-2` |
| Current software | **v1.0.1** ([release](https://github.com/oxygene76/medasdigital-2/releases/tag/v1.0.1), tag `v1.0.1`) |
| Denom | `umedas` (1 MEDAS = 1 000 000 umedas) |
| Address prefix | `medas` |
| Minimum gas price | `0.025umedas` |
| Genesis | [`genesis/mainnet/config/genesis.json`](genesis/mainnet/config/genesis.json), SHA-256 `e4c22a18aa3a9577fa0565785bc6dfe1648a43f47c0e6bbcb5f236a6f635f9b0` |
| RPC | `https://rpc.medas-digital.io:26657` |
| REST (LCD) | `https://lcd.medas-digital.io:1317` |
| gRPC | `grpc.medas-digital.io:9090` (TLS) |
| Explorer | _to be added_ |
| Peers | _to be added_ |

> **Upcoming mandatory upgrade: v2.** The network will upgrade to v2 through a
> governance proposal. All node operators must prepare for it. See
> [docs/upgrades/v2.md](docs/upgrades/v2.md).

## Run a node

Requirements:
- Linux x86_64 (amd64) with systemd; Ubuntu 22.04 or later is recommended.
- 4 CPU cores and 8 GB RAM.
- 100 GB+ free disk space for a node started with state sync, 250 GB+ for a full
  sync from genesis.
- Port 26656/tcp reachable for P2P.

> ⚠️ **Do not use release v1.0.0.** It is not compatible with the mainnet and
> cannot sync the chain. Older versions of `medasdigital_setup.sh` installed it
> as the "latest" release. The mainnet binary is **v1.0.1**.

### Quick start with the setup script (recommended)

[`medasdigital_setup.sh`](medasdigital_setup.sh) sets up a node the way the
network expects it:
- The node runs under [Cosmovisor](https://github.com/cosmos/cosmos-sdk/tree/main/tools/cosmovisor),
  so upgrades switch the binary automatically.
- Every download is verified by SHA-256: binary v1.0.1, libwasmvm 2.1.2,
  genesis and Cosmovisor.
- The node is initialized with state sync.
- The script never creates, imports or modifies validator keys or wallets.

```sh
curl -fsSLO https://raw.githubusercontent.com/oxygene76/medasdigital-2/main/medasdigital_setup.sh
chmod +x medasdigital_setup.sh
sudo ./medasdigital_setup.sh install                 # cosmovisor, libwasmvm 2.1.2, medasdigitald v1.0.1
sudo ./medasdigital_setup.sh init <your-moniker>     # state sync; add --genesis-sync for a full sync
sudo ./medasdigital_setup.sh service                 # systemd unit "medasdigitald"
sudo systemctl start medasdigitald
./medasdigital_setup.sh status                       # height, catching up, peers, upgrades
journalctl -fu medasdigitald
```

Settings can be changed with environment variables, for example:
- `NODE_USER` / `NODE_HOME`: run the node as a dedicated user.
- `STATE_SYNC_RPC` / `STATE_SYNC_RPC2`: RPC servers for state sync.
  `STATE_SYNC_RPC2` should be an independent second server.
- `PEERS`: persistent peers.

```sh
sudo NODE_USER=medas ./medasdigital_setup.sh install
```

The script supports one node per machine.

### Manual setup

1. **Binary v1.0.1** from the [GitHub release](https://github.com/oxygene76/medasdigital-2/releases/tag/v1.0.1):

   ```sh
   curl -fsSLO https://github.com/oxygene76/medasdigital-2/releases/download/v1.0.1/medasdigitald
   echo "676a9d2f4f0648994a7da8b30ab4fbbd69018bd82c23f1c077e2b01044871a68  medasdigitald" | sha256sum -c -
   sudo install -m 0755 medasdigitald /usr/local/bin/medasdigitald
   ```

2. **libwasmvm 2.1.2.** v1.0.1 is dynamically linked against this exact version:

   ```sh
   curl -fsSLO https://github.com/CosmWasm/wasmvm/releases/download/v2.1.2/libwasmvm.x86_64.so
   echo "015bdae5e70304f1e487981f90e3956754718fe7bdac4446aab0838fcb8b33e0  libwasmvm.x86_64.so" | sha256sum -c -
   sudo install -m 0644 libwasmvm.x86_64.so /usr/lib/libwasmvm.x86_64.so && sudo ldconfig
   medasdigitald version                       # v1.0.1
   medasdigitald query wasm libwasmvm-version  # 2.1.2
   ```

3. **Initialize and fetch the genesis:**

   ```sh
   medasdigitald init <your-moniker> --chain-id medasdigital-2
   curl -fsSL -o ~/.medasdigital/config/genesis.json \
     https://raw.githubusercontent.com/oxygene76/medasdigital-2/v1.0.1/genesis/mainnet/config/genesis.json
   echo "e4c22a18aa3a9577fa0565785bc6dfe1648a43f47c0e6bbcb5f236a6f635f9b0  $HOME/.medasdigital/config/genesis.json" | sha256sum -c -
   ```

4. **Configure:**
   - `persistent_peers` in `config.toml`: see [Network](#network).
   - `minimum-gas-prices = "0.025umedas"` in `app.toml`.
   - For state sync, set in the `[statesync]` section of `config.toml`:
     `enable = true`, two `rpc_servers`, and a recent `trust_height` /
     `trust_hash` taken from the RPC (`/block?height=<latest-2000>`).

5. **Run:** as a systemd service, ideally under Cosmovisor with v1.0.1 as the
   genesis binary. The setup script shows the exact unit.

## Existing nodes: switch to Cosmovisor

A node that runs `medasdigitald start` directly from a systemd unit can be
switched to Cosmovisor without touching its keys or data:

```sh
sudo ./medasdigital_setup.sh migrate
```

The script:
1. checks the running binary,
2. installs Cosmovisor,
3. copies the running binary as the Cosmovisor genesis binary,
4. shows the changes to the unit,
5. restarts the node once, after confirmation.

On a validator it also shows the voting power and how long the validator may be
offline before it gets jailed. At the end it prints the exact commands to
switch back:

```sh
sudo systemctl stop medasdigitald
sudo cp /etc/systemd/system/medasdigitald.service.pre-cosmovisor /etc/systemd/system/medasdigitald.service
sudo rm /usr/local/bin/medasdigitald && sudo mv /usr/local/bin/medasdigitald.pre-cosmovisor /usr/local/bin/medasdigitald
sudo systemctl daemon-reload && sudo systemctl start medasdigitald
```

The rollback is only valid until the next chain upgrade.

## Validators

- **Create the validator only after the node is fully synced**
  (`medasdigitald status | jq .sync_info.catching_up` → `false`).
- Create it with a JSON file:

  ```sh
  medasdigitald keys add <wallet>        # write down the mnemonic offline
  medasdigitald comet show-validator     # consensus public key for the JSON file
  medasdigitald tx staking create-validator --help
  medasdigitald tx staking create-validator validator.json --from <wallet> \
    --chain-id medasdigital-2 --gas auto --gas-adjustment 1.5 --gas-prices 0.025umedas
  ```

- **Back up your keys** offline and encrypted:
  - `config/priv_validator_key.json` (consensus key),
  - the wallet mnemonic,
  - `config/node_key.json` (optional).
- `data/priv_validator_state.json` belongs to the running node. Keep it with the
  key when you move a validator.
- **Never run the same `priv_validator_key.json` on two machines at the same
  time**, not even briefly during a move or with a standby node. Double signing
  slashes 5 % of the stake and tombstones the validator permanently.
- Downtime:
  - Missing more than 50 % of the blocks in the signing window jails the
    validator for 10 minutes and slashes 1 %.
  - `medasdigitald query slashing params` shows the current window.
  - Plan maintenance, and never stop several validators at the same time.

## Building from source

Release binaries are built from tags, never from `main`. See
[docs/building.md](docs/building.md) for the required Go version, a
reproducible build and how to compare the result with the published checksum.

## License

Licensed under the [Apache License 2.0](LICENSE).
