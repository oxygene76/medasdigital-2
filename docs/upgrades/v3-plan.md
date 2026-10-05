# Plan: upgrade `v3` (draft)

Status: **plan**, nothing implemented. Basis: v2.0.0 (Cosmos SDK v0.50.15,
ibc-go v8.8.0, wasmd v0.54.10 / wasmvm v2.2.9, CometBFT v0.38.26).

## Why

Cosmos SDK v0.50 is end of life: it receives no more fixes. Cosmos Labs
maintains two release families at a time:

| Family | Cosmos SDK | CometBFT | ibc-go |
|---|---|---|---|
| 2025.1 | v0.53.x | v0.38.x | v10.x |
| 2026.1 | v0.55.x | v0.40.x | v11.x |

There is no wasmd release for SDK v0.55 yet (wasmd v0.70 is built on SDK
v0.54, which belongs to no family). A chain with CosmWasm can therefore only
move to 2025.1 today. v3 does that, with a deliberately small scope.

## Target versions

| Component | v2.0.0 | v3 |
|---|---|---|
| Cosmos SDK | v0.50.15 | v0.53.x (currently v0.53.8) |
| ibc-go | v8.8.0 | v10.x (currently v10.7.0) |
| wasmd | v0.54.10 | v0.60.x (currently v0.60.9) |
| wasmvm | v2.2.9 | v2.3.x (currently v2.3.5), statically linked as before |
| CometBFT | v0.38.26 | v0.38.x, latest (same line, no consensus engine change) |
| Go | 1.26.8 | 1.26.x |

wasmd v0.60 keeps wasmvm 2. wasmd v0.61 would bring wasmvm 3; that is left out
on purpose, so that existing contracts run on the same VM generation.

## Scope

### In scope: only what the new versions require

1. **ibc-go v8 → v10**
   - Remove the capability module (keeper, scoped keepers, module) and the
     ICS-29 fee middleware (`feeibc`) from the transfer and ICA stacks.
   - New keeper signatures; ICA host with `ChannelKeeper` instead of
     `PortKeeper` and with the gRPC query router; light clients (07-tendermint,
     06-solomachine) registered as light client modules.
2. **Cosmos SDK v0.50 → v0.53**
   - auth PreBlocker in the module manager (mandatory).
   - x/mint: keep the default inflation function (`InflationCalculationFn` nil).
3. **wasmd v0.54 → v0.60**: new keeper wiring (no capability keeper), libwasmvm
   2.3.x pinned by sha256 in the Dockerfile.
4. **Store upgrades**: `Deleted: capability, feeibc`. Nothing added.
5. **Upgrade handler** `v3`: `RunMigrations` only; the module versions after
   the upgrade are recorded and checked like in v2.

### Out of scope (later upgrades)

- New optional modules (x/epochs, x/protocolpool), unordered transactions.
- Removing x/crisis, x/nft, x/circuit, x/group and x/params. They still work
  with SDK v0.53; they leave with the move to 2026.1, where they are moved to
  contrib or Cosmos Enterprise or removed.
- IBC v2 (Eureka), packet-forward middleware, callbacks.
- wasmvm 3 (wasmd v0.61).

## Facts from mainnet (read-only check, 5 October 2026)

| Item | State | Consequence |
|---|---|---|
| ICS-29 fee | 0 fee-enabled channels, 0 incentivized packets, no escrowed funds | removing `feeibc` loses nothing |
| IBC channels | 3 transfer channels, `ics20-1`, no fee wrapper | channels stay as they are |
| ICA host | enabled | wiring must be ported and tested |
| x/group, x/nft, x/circuit | empty | not touched in v3 |
| CosmWasm | 3 codes, 3 contracts | must keep working (test with the mainnet codes) |
| tokenfactory | no denoms | module version stays |

## Relayers

Hermes supports ibc-go v10 and Cosmos SDK v0.53 from **v1.13.1** on
(release note: “bumps the compatibility to ibc-go v10.0 and Cosmos SDK
v0.53”). The latest release is v1.13.3 (September 2025). All relayers serving
medasdigital-2 must run at least v1.13.1 before the upgrade height; v1.13.3
is recommended. The counterparty chains are not affected by our upgrade.

## Tests

1. Unit and app tests; `make proto-check`.
2. `scripts/upgrade-test.sh` with `OLD_BINARY` = v2.0.0 and `UPGRADE_NAME=v3`,
   extended by:
   - module versions before and after (capability and feeibc gone),
   - the three mainnet wasm codes (downloaded from mainnet, instantiated before
     the upgrade, executed after it),
   - an ICA host check.
3. IBC: two localnets connected by Hermes v1.13.3, a transfer channel opened on
   v2, packets relayed before the upgrade, one packet in flight across the
   upgrade height, packets in both directions after it.
4. Rehearsal on a copy of mainnet state, like for v2.

## Effort and risk

- Effort: about 1–2 weeks of work for code, tests and rehearsal, plus the
  governance timeline.
- Risk: medium. The main risk is the IBC rewiring (transfer and ICA stacks
  without capability and fee); a mistake could stall the existing channels.
  Mitigated by the IBC localnet test with a packet across the upgrade and by
  the rehearsal. CometBFT stays on v0.38, so there is no consensus engine
  change.
- Support horizon: 2025.1 is the older of the two supported families. Its end
  of support is not announced; it is expected when the next family is
  released. v3 should therefore be followed by the move to 2026.1 (or its
  successor) once wasmd supports it.

## Reserved: `v4` – notary module

The commit/reveal notary (`x/medasdigital`, `docs/notary-spec.md` on branch
`feat/notary`) is planned as upgrade `v4` on top of v3:
- protobuf messages and state as in the specification (including
  `content_sha256`, open point 13.7);
- `x/medasdigital` ConsensusVersion 1 → 2 with a migration; the module's store
  exists already, the new collections use new prefixes (spec section 7), so no
  store upgrade is needed;
- phase 0 records (memo anchors) stay valid and are not imported.

v4 is planned separately from the move to the 2026.1 family.
