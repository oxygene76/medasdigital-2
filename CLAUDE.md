# medasdigital-2

Cosmos SDK chain, originally scaffolded with Ignite (depinject, `app/app_config.go`).

| | |
|---|---|
| Mainnet chain ID | `medasdigital-2` |
| Binary | `medasdigitald` |
| Bech32 prefix | `medas` (`medasvaloper`, `medasvalcons`) |
| Denom | `umedas` |
| Stack | Cosmos SDK v0.50.10, CometBFT v0.38.21, wasmd v0.53.0 (wasmvm v2.1.2), ibc-go v8.5.1 |
| Go | 1.22.x (go.mod: 1.22.11, same as the mainnet binary) |

Layout:
- `app/` – app wiring. Most modules go through depinject (`app_config.go`); IBC and wasm are wired manually (`ibc.go`, `wasm.go`); ante handler in `ante.go`.
- `x/medasdigital` – custom module, still the unchanged Ignite scaffold (empty params, only `MsgUpdateParams`, ConsensusVersion 1). This is where the planned commit/reveal notary goes.
- `x/tokenfactory` – token factory module (ConsensusVersion 1).
- `proto/` – protobuf sources and buf templates. Generated code goes to `x/*/types` (gogo) and `api/` (pulsar).
- `genesis/mainnet/` – mainnet genesis. `binaries/` – historically committed release binaries (do not add new ones, see below).

## Build

Needs Go 1.22.x **and a C compiler** (gcc): wasmvm requires CGO. Without gcc, CGO
is silently off and wasmd fails to compile (`NewKeeper` type errors in
`x/wasm/keeper/test_common.go`).

```sh
make build          # -> bin/medasdigitald, tags "netgo ledger", same flags as the release
go build ./...
```

The binary links `libwasmvm.x86_64.so` dynamically; a local build finds it through
its RUNPATH in the Go module cache.

`make build` fails on purpose if Go is not 1.22.x (consensus safety). Do not bump
the Go version without coordinating with the validators.

## Test

```sh
go test ./...
```

Only the Ignite default tests exist (`app`, `x/*/keeper`, `x/*/module`, `x/*/types`).

## Protobuf

```sh
make proto-gen      # regenerate *.pb.go, *.pb.gw.go, *.pulsar.go
make proto-check    # regenerate and fail if the committed files differ
```

Runs buf directly with buf and the plugins at the versions pinned in `go.mod`
(`tools/tools.go`), installed into `build/tools`. No Ignite and no Docker needed; the
first run needs network access to buf.build for the deps in `proto/buf.lock`.
This reproduces the committed generated files byte for byte.

Never edit generated files by hand. Change the `.proto` and run `make proto-gen`.

## Local testnet

```sh
make build
scripts/localnet.sh          # = up: wipe ./.localnet, fresh chain, start node, smoke test
scripts/localnet.sh init     # wipe + fresh chain, without starting it
scripts/localnet.sh start    # (re)start the existing chain; BINARY=... selects the binary
scripts/localnet.sh status   # height and balances
scripts/localnet.sh smoke    # bank-send smoke test against the running node
scripts/localnet.sh stop
```

- Chain ID `medasdigital-local`, denom `umedas`, home `./.localnet/home`, log `./.localnet/node.log`.
- Test keyring (`--keyring-backend test --home .localnet/home`) with `validator`, `alice`, `bob`.
- Gov voting period and max deposit period 60s (expedited 30s), block time about 1s.
- Listens on 127.0.0.1 only. Ports: RPC 36657, P2P 36656, gRPC 39090, REST 11317 (override with `RPC_PORT`, `P2P_PORT`, `GRPC_PORT`, `API_PORT`).

Example CLI call against the localnet:

```sh
bin/medasdigitald --home .localnet/home q bank balances $(bin/medasdigitald --home .localnet/home keys show alice -a --keyring-backend test) --node tcp://127.0.0.1:36657
```

## Upgrades

Mainnet (v1.0.1) has never been upgraded through `x/upgrade`. The infrastructure
exists since branch `feat/upgrade-v2`; the first mainnet upgrade will be `v2`.

Layout:
- `app/upgrades/types.go`: `upgrades.Upgrade{UpgradeName, CreateUpgradeHandler, StoreUpgrades}`.
- `app/upgrades/<name>/`: one package per upgrade (currently `v2`, which only runs `RunMigrations`).
- `app/upgrades.go`: the `Upgrades` list, `setUpgradeHandlers()` and
  `setUpgradeStoreLoader()`. The store loader reads `data/upgrade-info.json`, is
  skipped for `--unsafe-skip-upgrades` heights, and is only set for known plan names.
- `app/app.go` calls both **after** `registerIBCModules` and **before** `app.Load()`:
  - The handlers migrate over the whole module manager, which must include the
    manually wired IBC and wasm modules.
  - `app.Load()` seals the BaseApp, and `SetStoreLoader` panics after that.

Adding an upgrade:
1. Create `app/upgrades/vN/upgrades.go` with `UpgradeName = "vN"`, a handler that
   runs `mm.RunMigrations` plus any custom logic, and `StoreUpgrades`. New modules
   go into `Added`, which is required, otherwise their store is missing.
2. Append it to `Upgrades` in `app/upgrades.go`. Never remove an upgrade that has
   been applied on mainnet: the binary would then refuse to process blocks.
3. For changed module state, bump that module's `ConsensusVersion` and register a
   migration in its `RegisterServices`.
4. Run `scripts/upgrade-test.sh` (with `UPGRADE_NAME=vN`, and `OLD_REF` = the
   currently deployed release).

Upgrade test (`scripts/upgrade-test.sh`, about 3 minutes, no Cosmovisor):
- `make build-upgrade-binaries` builds `build/old` from `OLD_REF` (default
  `050907c` = v1.0.1 code, built with that commit's Makefile in a temporary
  worktree) and `build/new` from the checkout.
- It then runs the full flow: fresh localnet with old, gov proposal (height =
  now + `UPGRADE_BUFFER`, default 100), deposit, vote, wait for "PASSED", wait for
  `UPGRADE "v2" NEEDED`, swap binary, verify (blocks, `query upgrade applied`,
  plan cleared, module versions unchanged, bank send).
- `SKIP_BUILD=1` reuses existing binaries.

Behaviour worth knowing (verified on the localnet):
- **At the upgrade height the old binary does not exit.** It logs
  `UPGRADE "v2" NEEDED` and `CONSENSUS FAILURE!!!`, and the process keeps running.
  `/status` then shows the upgrade height (the block is stored), while
  `/abci_info` shows the last committed app height (one lower). Stop it and start
  the new binary.
- **Old binary after the upgrade:** it starts, then fails at the first block with
  `wrong app version 0, upgrade handler is missing for v2 upgrade plan`. Nothing
  is committed, and the new binary continues cleanly.
- **New binary before the upgrade height:** with a passed plan it fails with
  `BINARY UPDATED BEFORE TRIGGER!`, commits nothing, and the old binary continues
  cleanly. Without any plan the new binary runs normally.
- Gov txs on the localnet use fixed gas (`--gas 400000`): `--gas auto`
  underestimates `MsgVote`.

## Mainnet state

Verified on a validator:
- `/usr/local/bin/medasdigitald` sha256
  `676a9d2f4f0648994a7da8b30ab4fbbd69018bd82c23f1c077e2b01044871a68`, identical to
  `binaries/v1.0.1/medasdigitald`. It reports commit `a77373b` but has the
  dependencies of `050907c` (CometBFT v0.38.21); the app code of both commits is identical.
- `genesis.json` sha256
  `e4c22a18aa3a9577fa0565785bc6dfe1648a43f47c0e6bbcb5f236a6f635f9b0`, identical to
  `genesis/mainnet/config/genesis.json` on `main` (last commit `9f506bd`).

## Rules

- Never work on `main`. Use feature branches.
- No transactions against mainnet or public RPCs. No real keys. Do not touch keyring
  files outside `./.localnet`.
- Never edit generated files (`*.pb.go`, `*.pulsar.go`, `*.pb.gw.go`) by hand; regenerate them.
- Changes to consensus-relevant code (anything that changes state transitions or
  app hash) only when explicitly asked for, and always together with an upgrade plan.
- If something is unclear or a decision is pending, stop and ask instead of guessing.
- Small, traceable commits with meaningful messages. Commit as soon as an
  intermediate step works (not only at the end of a task), so there is always a
  known good state to return to, especially for upgrade or consensus code.
- Do not set tags and do not commit binaries. Releases go through git tags and
  GitHub Releases, not the `binaries/` directory.
