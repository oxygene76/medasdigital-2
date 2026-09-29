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

## Upgrade infrastructure: missing

There is **no upgrade handler** anywhere in the repo (no `SetUpgradeHandler`, no
`StoreUpgrades`), and the chain has never been upgraded via `x/upgrade`. Before the
first state-breaking change (e.g. new messages or state in `x/medasdigital`) this is
needed:
- an `app/upgrades` package with a handler that runs `RunMigrations`,
- `ConsensusVersion` bumps and migrations for changed modules,
- a rehearsal on the localnet (gov proposal, then halt, then binary swap).

## Rules

- Never work on `main`. Use feature branches.
- No transactions against mainnet or public RPCs. No real keys. Do not touch keyring
  files outside `./.localnet`.
- Never edit generated files (`*.pb.go`, `*.pulsar.go`, `*.pb.gw.go`) by hand; regenerate them.
- Changes to consensus-relevant code (anything that changes state transitions or
  app hash) only when explicitly asked for, and always together with an upgrade plan.
- If something is unclear or a decision is pending, stop and ask instead of guessing.
- Small, traceable commits with meaningful messages.
- Do not set tags and do not commit binaries. Releases go through git tags and
  GitHub Releases, not the `binaries/` directory.
