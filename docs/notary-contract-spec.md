# medas notary: CosmWasm contract specification

Status: **draft for review**, no code yet
Basis: [notary-spec.md](notary-spec.md) (commitment hash, evaluation rules, phase 0)
Target: medasdigital-2 as it runs today (v2.0.0: wasmd v0.54.10, wasmvm v2.2.9), **without a chain upgrade**

The key words MUST, MUST NOT, SHOULD and MAY are used as described in RFC 2119.
Section 15 lists the decisions that are still open.

## 1. Purpose and principles

The notary becomes a CosmWasm contract instead of a native module. It records
commitments and their reveals (notary-spec.md sections 1 to 3), who was a
registered researcher, and who was an admin, and it checks reveals on chain.

1. **Only hashes and addresses on chain.** The contract stores no content, no
   payload, no free text (no label, no schema name) and no personal data such
   as names or institutions. Addresses are pseudonyms; whoever knows the person
   behind an address can link the entries to that person, as on every public
   chain.
2. **Same commitment hash as phase 0.** The hash is protocol version 1 of
   notary-spec.md section 3, unchanged. Receipts, test vectors and the
   reference script stay valid.
3. **No chain upgrade.** The contract uses only what the current chain offers
   and MUST keep running unchanged after `v3` (wasmd v0.60, wasmvm v2.3).
4. **Proof layer only.** For computation jobs (section 5) the contract proves
   job and result. Payment, escrow and settlement stay outside.
5. **Checkable history.** Everything needed to judge an entry later (who was
   admin, who was registered, at which block time) is in the contract state
   with its history, not in an off-chain file.

## 2. Platform and compatibility

| Item | Value |
|---|---|
| Chain today | wasmd v0.54.10, wasmvm v2.2.9, capabilities up to `cosmwasm_2_2` |
| After v3 | wasmd v0.60.x, wasmvm v2.3.x (same VM generation) |
| Contract framework | cosmwasm-std 2.2.x, cw-storage-plus 2.x, cw2 |
| Required capabilities | `iterator`, `cosmwasm_1_3` (community pool message), nothing above `cosmwasm_2_2` |
| Not used | IBC entry points, sudo, stargate/any messages, submessage replies, floats |

- The build checks the required capabilities (`cosmwasm-check
  --available-capabilities` with the list of wasmd v0.54.10).
- Contract state lives in the wasm module's store. `v3` deletes the stores
  `capability` and `feeibc`; the contract uses neither IBC nor fees of ICS-29,
  so nothing it depends on changes.
- A later move to wasmvm 3 (wasmd v0.61 or later) is out of scope here; the
  contract is to be re-tested before such an upgrade.
- Facts checked on mainnet (13 October 2026): uploading code is restricted to
  one address (`code_upload_access: AnyOfAddresses`), instantiating is open to
  everybody; the wasm module account may burn coins (needed for section 6).

## 3. Messages, queries and state

Hashes and salts are passed and returned as 64 lowercase hex characters.
Addresses are bech32 with prefix `medas`. Times are block times (nanoseconds
since the epoch in state, RFC 3339 in query responses).

### 3.1 Instantiate

```
InstantiateMsg {
  fee: Coin,                      // per commit; pilot: 1000000000 umedas (1,000 MEDAS); amount 0 = no fee
  fee_split: FeeSplit,            // section 6
  start_credit: Coin,             // minimum an approval must carry; pilot: 1002000000 umedas (section 7)
  require_registration: bool,     // true: only registered addresses may commit
  admins: [address],              // initial notary admins (section 8), valid from this block
  phase0_registrations: [         // optional, section 11
    { address, approve_tx: hex }
  ]
}
```

### 3.2 Execute

| Message | Sender | Funds | Effect |
|---|---|---|---|
| `Commit { hash, entry_type, reference }` | creator | exactly `fee` | stores a commit (section 4) |
| `Reveal { id, salt, content_sha256 }` | anybody | none | checks and stores the reveal (section 4) |
| `Approve { address }` | notary admin | at least `start_credit` | registers the address, forwards the funds to it (section 7) |
| `Revoke { address }` | notary admin | none | ends the registration (section 7) |
| `SetAdmin { address, active }` | contract admin | none | adds or retires a notary admin (section 8) |
| `UpdateParams { fee?, fee_split?, start_credit?, require_registration? }` | contract admin | none | changes parameters from this block on |

Every message MUST be rejected if it carries funds other than stated, and the
contract MUST NOT keep any balance: all funds it receives are forwarded,
distributed or burnt in the same transaction.

### 3.3 Queries

| Query | Returns |
|---|---|
| `Config {}` | parameters, contract name and version, number of commits |
| `Commit { id }` | one commit |
| `Commits { start_after?, limit? }` | commits in id order |
| `CommitsByCreator { creator, start_after?, limit? }` | all commits of an address, revealed or not (evaluation rule 12.3) |
| `CommitsByHash { hash }` | all commits with this hash (at most one per creator) |
| `References { id, start_after?, limit? }` | commits that refer to `id` (e.g. the results of a job) |
| `Registration { address }` | current status and the full history of approvals and revocations |
| `Registrations { start_after?, limit? }` | addresses with a registration history |
| `Admins {}` | every notary admin with all its validity periods |
| `AdminAt { address, time }` | whether the address was a notary admin at that block time |

`limit` defaults to 30 and is capped at 100. All queries are deterministic and
bounded, so other contracts may call them.

### 3.4 State

| Key | Type | Content |
|---|---|---|
| `config` | item | `fee`, `fee_split`, `start_credit`, `require_registration` |
| `next_id` | item | next commit id, starts at 1 |
| `commits` | map `id` → `Commit` | section 4 |
| `by_hash` | map `(hash, creator)` → `id` | uniqueness of (creator, hash); `CommitsByHash` |
| `by_creator` | map `(creator, id)` → () | `CommitsByCreator` |
| `refs` | map `(referenced id, id)` → () | `References` |
| `registrations` | map `address` → list of `{ kind, admin, height, time, origin }` | section 7 |
| `admins` | map `address` → list of `{ from_height, from_time, until_height?, until_time? }` | section 8 |
| cw2 `contract_info` | item | name `medas-notary`, semantic version |

Nothing is ever deleted. A commit changes exactly once, when it is revealed.

### 3.5 Events

`wasm-notary_commit { id, creator, hash, entry_type, reference, registered }`,
`wasm-notary_reveal { id, creator, revealer }`,
`wasm-notary_approve { address, admin }`, `wasm-notary_revoke { address, admin }`,
`wasm-notary_admin { address, active }`, `wasm-notary_params { … }`.
Indexers can follow the contract with the transaction search
`wasm._contract_address='<address>'`; the state queries are the source of
truth.

## 4. Commit and reveal

### 4.1 Stored commit

| Field | Set at | Content |
|---|---|---|
| `id` | commit | sequential, first is 1 |
| `creator` | commit | sender of `Commit` |
| `hash` | commit | commitment hash, 32 bytes |
| `entry_type` | commit | `note`, `job` or `result` (section 5) |
| `reference` | commit | optional id of an earlier commit |
| `commit_height`, `commit_time` | commit | block of the commit |
| `registered` | commit | whether the creator was registered in this block (section 7) |
| `fee_paid` | commit | the fee that applied |
| `revealed`, `revealer`, `salt`, `content_sha256`, `reveal_height`, `reveal_time` | reveal | empty until revealed |

### 4.2 Commit

`Commit` MUST be rejected unless all of the following hold:
1. The sender's address bytes are 20 or 32 bytes long (notary-spec.md 3.1).
2. `hash` is exactly 32 bytes.
3. No commit with the same (creator, hash) exists.
4. The attached funds are exactly `fee` (no funds if the fee amount is 0).
5. If `require_registration` is true: the sender is registered in this block.
6. The rules for `entry_type` and `reference` of section 5.

### 4.3 Reveal, checked by the contract

`Reveal` MUST be rejected unless all of the following hold:
1. The commit `id` exists and is not yet revealed.
2. `salt` and `content_sha256` are exactly 32 bytes each.
3. `SHA-256("medas-notary/v1" || len(creator_bytes) || creator_bytes || salt
   || content_sha256) == commit.hash`, with `creator_bytes` the canonical bytes
   of the commit's creator (notary-spec.md 3.1). The contract computes SHA-256
   itself.

The content is never sent to the contract. Whoever holds the content proves it
by hashing it and comparing with `content_sha256` (evaluation rule 12.7).
There is no deadline for revealing.

Any address may send `Reveal`, as in notary-spec.md 5.2: the salt is the only
key, a reveal exposes salt and digest in the mempool anyway, and attribution
follows from the creator bound into the hash. `revealer` MUST NOT be read as
authorship. (Phase 0 accepted reveals only from the creator, because a memo
anchor cannot be checked by the chain; see section 15.)

### 4.4 Differences to the earlier module design (notary-spec.md 4 to 11)

- No `payload`, `label` and `schema`: principle 1. The schema of a payload
  belongs into the payload itself (notary-spec.md 13.3, second option).
- `entry_type` and `reference` are new (section 5).
- `registered` and `fee_paid` are recorded on the commit.
- Parameters, admins and registrations are contract state with history.

## 5. Entry types and references

| `entry_type` | Meaning | `reference` |
|---|---|---|
| `note` | a plain record (the only kind in phase 0) | optional: an earlier entry it builds on |
| `job` | the specification of a computation job | optional: an earlier entry, e.g. a job it supersedes |
| `result` | the result of a job | REQUIRED: the id of a `job` |

- A reference MUST point to an existing commit with a lower id. Because ids
  are assigned in transaction order, the referenced entry is always earlier.
- The creator of a `result` may differ from the creator of the `job` (the
  party that computes is usually not the party that orders).
- `entry_type` and `reference` are **not** part of the commitment hash. They
  are public at commit time, stored immutably with the commit and signed by
  the creator as part of the transaction; the hash keeps its only task, hiding
  the content until the reveal. This keeps protocol version 1 and the phase 0
  receipts valid.
- What a job or a result contains (job type, inputs, output) is defined off
  chain by published, versioned job types (notary-spec.md 17); on chain there
  are only their hashes.
- Payment, escrow and settlement for jobs are **not** part of this contract. A
  later contract can refer to commits by id and query them.

## 6. Fee, split and burn

Each commit costs `fee` (a parameter; the transaction fee of the chain comes
on top). The contract splits it in the same transaction:

```
FeeSplit {
  burn_bps: u16,                          // burnt (BankMsg::Burn)
  community_pool_bps: u16,                // community pool (DistributionMsg::FundCommunityPool)
  recipients: [{ address, bps: u16 }]     // paid out (BankMsg::Send), at most 5
}
```

- The sum of all shares MUST be 10000 basis points.
- Each share is `floor(fee * bps / 10000)`; the rounding remainder is added to
  the burnt part.
- Burning reduces the supply of `umedas`; it is visible in the supply query and
  in the transaction events.
- `UpdateParams` changes fee and split for later commits only; `fee_paid` on
  each commit records what applied.
- Reveals, approvals and revocations cost no notary fee.

### 6.1 Pilot values (decided)

| Parameter | Pilot |
|---|---|
| `fee` | 1,000 MEDAS per entry (`1000000000umedas`) |
| `burn_bps` | 10000 (100 % burnt) |
| `community_pool_bps` | 0 |
| `recipients` | none |

The split stays in the code and in the parameters for later; in the pilot
every fee is burnt completely.

### 6.2 Network fees: measured gas

Measured on a localnet with the v2.0.0 binary and a throwaway prototype that
follows the state layout and checks of this specification (commit with all
indexes, reveal with SHA-256 check, approval, fee burn). The real contract
will differ somewhat; the values are to be measured again with it (test plan).

| Transaction | Gas used | Gas wanted (simulation × 1.3) | Fee at 0.025 umedas/gas |
|---|---|---|---|
| commit, fee paid and burnt | 198,000 – 212,000 | about 250,000 | 0.0063 MEDAS |
| reveal | 144,000 | about 161,000 | 0.0040 MEDAS |
| approve (burn and forward) | 200,000 | about 235,000 | 0.0059 MEDAS |

100 transactions (for example 50 commits and 50 reveals) cost about 0.5 MEDAS,
100 commits about 0.63 MEDAS. **Proposed reserve for network fees: 2 MEDAS**
(about 100 transactions with a margin of a factor 3 for the real contract and
for a higher gas price). The network fee is negligible next to the notary fee
of 1,000 MEDAS per entry.

## 7. Registration: approval and revocation

- `Approve { address }` by a notary admin registers the address. The attached
  funds (at least `start_credit`, in the fee denom) are forwarded to the
  address in the same transaction, as the starting credit.
- **Pilot:** `start_credit` = **1,002 MEDAS**: one entry (1,000 MEDAS) plus a
  reserve of 2 MEDAS for network fees (section 6.2). There are no prepaid
  entries or quotas: every commit pays the fee.
- Researchers buy further MEDAS themselves, e.g. on Osmosis. If the balance of
  the connected address is lower than `fee` plus the network fee of a commit,
  the web application says so before the commit and links to the MEDAS pool
  on Osmosis (section 12).
- `Revoke { address }` by a notary admin ends the registration.
- Both MUST be rejected unless the sender is a notary admin **in this block**
  (section 8). Both append `{ kind, admin, height, time }` to the address's
  history; nothing is overwritten.
- An address is registered at a point of the chain if the last entry of its
  history before that point is an approval (same rule as notary-spec.md 16.4).
  The contract evaluates this at commit time and stores the result on the
  commit (`registered`), so clients need not recompute it.
- Retiring an admin later does not affect approvals and revocations it made
  while it was an admin.
- Names, institutions and reasons stay off chain, with the researcher's
  consent, as in phase 0.

## 8. Notary admins in the contract

The admin list moves from `docs/notary/admins.json` into the contract.

- `SetAdmin { address, active: true }` opens a validity period starting with
  the current block (height and time); `active: false` closes the open period
  with the current block. Periods are never deleted or edited, so a later
  period after a pause is a new entry.
- An address is a notary admin at time `t` if one of its periods satisfies
  `from_time <= t < until_time` (open period: no upper bound).
- `Admins {}` returns all addresses with all periods; `AdminAt` answers for a
  given time. With the histories of section 7 anybody can check from the
  contract state alone who was admin when an approval was made.
- Only the **contract admin** (section 9) may send `SetAdmin` and
  `UpdateParams`. Notary admins cannot change the list or the parameters.

## 9. Contract admin

The contract admin is the admin of the contract instance in the wasm module
(the address that may migrate it). The contract reads it from the chain
(contract info query) on every `SetAdmin` and `UpdateParams`; there is no
second owner field that could diverge.

- **Pilot:** an address created by the operators and used for nothing else
  (no notary admin, no relayer, no validator key), kept offline between uses.
  It can change the admin list and the parameters and migrate the contract to
  new code.
- **Afterwards:** hand-over to governance with `MsgUpdateAdmin` to the address
  of the gov module. From then on parameter changes, admin changes and
  migrations need a governance proposal (`MsgExecuteContract` or
  `MsgMigrateContract` with the gov module as sender).
- Migrations: the `migrate` entry point accepts only the same contract name
  and a higher version, and MUST keep all commits, histories and ids.
- If the contract admin is cleared (`MsgClearAdmin`), the contract is frozen:
  no migrations, no parameter or admin changes. Not planned.

## 10. Build, upload and instantiation

1. **Reproducible build.** Built with the CosmWasm optimizer image pinned by
   digest and a pinned Rust toolchain, from a tagged commit, with
   `Cargo.lock` committed and `--locked`. The build writes the `.wasm` file
   and its sha256; two independent builds MUST give the same hash.
   - **Toolchain limit (checked on the localnet):** wasmvm 2.2 rejects Wasm
     built with Rust 1.82 or later ("zero byte expected": the reference-types
     encoding these compilers emit by default). The contract MUST be built
     with Rust 1.81 or an optimizer image based on it, and
     cosmwasm-std MUST stay on the 2.2 line (`~2.2`); newer dependency
     versions that need a newer compiler are excluded by the lock file.
   - The build MUST include storing the result on a localnet with the
     mainnet binary, so that a Wasm the chain does not accept is never
     released.
2. **Published code hash.** The sha256 of the `.wasm` file is published with
   the release, in this repository (`docs/notary/contract.json`, see below)
   and on the Methodology page of the web application. On chain it is the
   checksum of the code: `medasdigitald q wasm code-info <code_id>`.
3. **Upload.** Code upload on mainnet is restricted to one address. Either
   that address stores the code, or a governance proposal does
   (`MsgStoreCode` with the gov module as sender). The code is stored with
   instantiate permission limited to the contract admin, so that no second
   instance of the same code can be mistaken for the notary.
4. **Instantiation** by the contract admin, with `--admin <contract admin>`,
   the label `medas-notary` and the `InstantiateMsg` of 3.1.
5. **Record.** `docs/notary/contract.json` lists, per network: code id, code
   hash, contract address, instantiation transaction, source repository and
   tag. Clients pin this file at a commit, like the admin list in phase 0.
6. **Check after instantiation:** code hash on chain equals the published
   hash; `Config` returns the intended parameters; the contract admin is the
   pilot address; `Admins` lists the intended notary admins.

## 11. Phase 0 entries

- Phase 0 anchors (memo transactions to the keyless address, notary-spec.md
  16) **stay valid and are not imported**. The contract cannot read the
  chain's transaction history, and importing them through an admin would
  replace a fact everybody can check by a claim of the importer.
- The commitment hash is the same. The same (creator, hash) may exist as a
  phase 0 anchor and as a contract commit; the earlier one establishes
  priority (evaluation rule 12.1). Clients show both sources and name the
  source of each entry.
- New entries go to the contract once it is live. Phase 0 commits can still be
  revealed the phase 0 way.
- Phase 0 registrations: approvals by memo stay the record for the phase 0
  period. To avoid approving and funding the same researchers twice, the
  instantiation MAY seed registrations (`phase0_registrations`): each seeded
  address gets a history entry with `origin: phase0` and the hash of its
  phase 0 approve transaction, so the entry can be checked against the chain.
- `docs/notary/admins.json` stays the admin list for the phase 0 period and
  gets no new entries after the contract is live.

## 12. Consequences for indexer and web application

**Profile service and index**
- The index follows the contract instead of memo transfers: transaction
  search by contract address for new events, contract queries
  (`Commits`, `Registration`, `Admins`) as source of truth. The phase 0 index
  is kept and shown as a second source.
- Approvals are checked against `Registration` in the contract instead of
  decoding a bank transfer; the admin list comes from `Admins` (with history)
  instead of the pinned `admins.json`.
- The backfill becomes a paginated read of the contract state; any node with
  the current state is enough (no full transaction index needed for contract
  data).
- The read-only node's proxy must also allow smart queries (`abci_query` for
  `/cosmwasm.wasm.v1.Query/SmartContractState`, GET only).

**Web application**
- Commit, reveal, approve and revoke become `MsgExecuteContract` (Keplr and
  Leap sign it in direct and amino mode). Fee and starting credit come from
  `Config`, not from build-time constants.
- Before a commit the site compares the balance with `fee` plus the network
  fee. If it is not enough, it shows a notice with a link to the MEDAS pool on
  Osmosis (the pool id is configuration, not code) instead of the commit
  button.
- The receipt stays as it is (creator, hash, salt, content digest) and gets
  the contract address and the commit id.
- The directory shows entry type and reference, and `registered` from the
  commit itself.
- Methodology page: contract address, code id, code hash and how to verify
  them; the pinned `contract.json` replaces the pinned admin list.
- Admin page: the list of admins and its history are read from the contract;
  changing it is not a function of the site (contract admin only).

## 13. Where the code lives

Proposal: an own public repository **`medas-notary-contract`** (Rust
workspace: contract, schema, tests, build script), with tagged releases that
carry the `.wasm` file and its sha256.

- Keeps the Go chain repository free of a Rust toolchain; chain releases and
  contract releases have independent versions.
- This repository keeps the specifications, the hash test vectors,
  `docs/notary/contract.json` and the upgrade test, which downloads the
  released `.wasm` by sha256.
- Alternative: `contracts/notary/` in this repository. One place for
  everything, but Rust builds and audits mix with consensus code.

## 14. Test plan

**Unit and contract tests** (cw-multi-test)
- hash test vectors of `x/medasdigital/types/testdata/notary_hash_vectors.json`,
  including the negative ones; 20 and 32 byte creators;
- commit: duplicate (creator, hash), wrong hash length, wrong funds,
  unregistered sender with `require_registration`;
- reveal: wrong salt, wrong digest, second reveal, reveal by another address;
- entry types: `result` without reference, reference to a later or missing id,
  reference to a non-job;
- fee split: shares, rounding remainder, fee 0, parameter change between two
  commits (`fee_paid`);
- registration: approve, revoke, approve again; history; `registered` on
  commits before and after; approval below `start_credit`;
- admins: periods, retired admin cannot approve, earlier approvals stay
  valid, `AdminAt` at period borders;
- authority: `SetAdmin` and `UpdateParams` by anybody but the contract admin
  fail; migration keeps state and rejects lower versions;
- no balance left on the contract after any message.

**Localnet** (`scripts/localnet.sh`, static v2.0.0 binary)
1. Store with restricted upload permission (as on mainnet), instantiate with
   admin; compare the code hash.
2. Full flow with real transactions: approve (starting credit arrives),
   commit, reveal, revoke; job with two results and `References`.
3. Supply before and after commits (burn), community pool and recipient
   balances.
4. Gas of commit and reveal, recorded in the specification; query pagination
   with a few thousand commits.
5. Hand-over of the contract admin to the gov module and a parameter change
   by governance proposal.
6. Web application end to end against this localnet (Keplr signing of
   `MsgExecuteContract`).

**Upgrade rehearsal** (in the `v3` plan): the released `.wasm` is stored and
used on v2, the chain is upgraded, then the code hash and all queries are
compared, an entry committed before the upgrade is revealed after it, and new
entries are made.

## 15. Comparison with a native module, and open decisions

| | Contract | Native module (earlier plan, `v4`) |
|---|---|---|
| Needs a chain upgrade | no, runs on today's chain | yes, coordinated with all validators |
| Changes later | migration by the contract admin, later by governance | another chain upgrade |
| Risk for consensus | isolated in the VM, gas-metered | bug can halt the chain |
| Gas and fees | higher per transaction (VM, JSON) | lower |
| Queries, clients | smart queries (JSON), CosmWasm clients | gRPC/REST, AutoCLI, typed events |
| Trust | contract admin can migrate until hand-over to governance | governance only |
| Genesis export | part of the wasm state | own genesis section |
| Time to mainnet | upload and instantiation | upgrade cycle |

Open decisions:
1. ~~Fee and split~~ **decided:** 1,000 MEDAS per entry, 100 % burn in the
   pilot (section 6.1).
2. `require_registration` in the pilot: true (as the web application does
   today) or open commits with `registered` shown.
3. Reveal by anybody (this draft) or only by the creator (as in phase 0).
4. Seeding phase 0 registrations at instantiation, or approving again.
5. Upload by the permitted address or by governance proposal.
6. Repository for the code (section 13).
7. The address of the pilot contract admin and the time of the hand-over to
   governance.
8. ~~How a researcher gets the means for entries~~ **decided (variant b,
   15 October 2026):** starting credit of 1,002 MEDAS with the approval, no
   quota; further MEDAS from Osmosis (section 7).
