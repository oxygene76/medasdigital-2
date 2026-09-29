# medas notary: commit–reveal specification

Status: **draft for review**, protocol version 1
Chain: medasdigital-2 (module `x/medasdigital`, introduced with software upgrade `v2`)
Reference implementation of the hash: [`scripts/notary_hash.py`](../scripts/notary_hash.py)
Test vectors: [`x/medasdigital/types/testdata/notary_hash_vectors.json`](../x/medasdigital/types/testdata/notary_hash_vectors.json)

The key words MUST, MUST NOT, SHOULD and MAY are used as described in RFC 2119.
Section 13 (open points) is not normative.

## 1. Purpose

The notary lets an address prove that it had fixed a statement (for example an
orbit prediction) at a certain time, **without disclosing the statement at
that time**.

1. **Commit.** The author publishes only a hash of the statement. The chain
   records the author's address, block height and block time.
2. **Reveal.** Later, anyone publishes the statement together with a secret salt.
   The chain checks that it matches the hash and makes it permanently public.

The hash binds the statement to the committing address. A hash copied by
someone else can never be revealed under the copier's address (section 3.3).

The chain treats the statement as opaque bytes. It does not interpret,
validate or rank statements; evaluation happens off-chain (section 12).

## 2. Terminology

| Term | Meaning |
|---|---|
| creator | Address that signed `MsgCommit`. Bound into the hash. |
| revealer | Address that signed `MsgReveal`. Any address; carries no meaning for attribution. |
| salt | 32 secret random bytes chosen by the creator. |
| payload | The statement, as bytes. Clients SHOULD use canonical JSON (RFC 8785). |
| schema | Public name of the payload format, e.g. `orbit.prediction.v1`. |
| label | Optional public free text attached to a commit. |
| block time | CometBFT BFT time of the block, as reported in the block header. |

## 3. Commitment hash (protocol version 1)

### 3.1 Definition

```
preimage = "medas-notary/v1"           15 bytes, ASCII, no terminator
        || uint8(len(creator_bytes))   1 byte: 20 (0x14) or 32 (0x20)
        || creator_bytes               raw address bytes, 20 or 32
        || salt                        exactly 32 bytes
        || payload                     all remaining bytes, at least 1

hash = SHA-256(preimage)               32 bytes
```

- `creator_bytes` MUST be the bytes obtained by bech32-decoding (BIP-173,
  prefix `medas`) the creator address. Examples: 20 bytes for accounts from
  secp256k1 keys, 32 bytes for CosmWasm contracts and other derived addresses.
  Addresses of other lengths cannot use protocol version 1 (see 5.1).
- `salt` MUST be exactly 32 bytes and SHOULD come from a cryptographically secure
  random number generator (e.g. `secrets.token_bytes(32)`, `crypto.getRandomValues`).
  Never reuse a salt.
- `payload` is everything after the salt. Because the salt has a fixed length
  and the creator is length-prefixed, the preimage is unambiguous.

### 3.2 Payload encoding (client convention)

The chain does not check the payload content. For interoperability, clients
SHOULD encode JSON payloads canonically according to RFC 8785 (JCS): sorted keys,
no insignificant whitespace, UTF-8.

Recommendations:
- Represent non-integer numbers as strings (e.g. `"ra_deg": "123.456789"`),
  because JCS number formatting is easy to get wrong.
- Keep integers within ±(2^53−1).
- Include a `schema` field inside the payload (see 13.3).

The reference script rejects floats for this reason. Any byte sequence of at
least 1 byte is a valid payload for the chain, including non-UTF-8 data
(test vector 4).

### 3.3 Properties

- **Hiding.** Without the salt, the hash reveals nothing about the payload, even
  for guessable payloads, because the salt has 256 bits of entropy.
- **Binding.** Finding a second (salt, payload) pair for the same hash is
  infeasible (SHA-256 collision resistance).
- **Creator binding.** Suppose address B copies A's hash. Then B's commit can
  only be revealed with a preimage containing B's address bytes. That preimage
  differs from the one A hashed, so B's copy is never revealable.
- **Domain separation.** The prefix `medas-notary/v1` separates this hash from
  other uses of SHA-256 and from future protocol versions.
- **No chain binding.** The chain ID is not part of the preimage. Priority is
  only defined on medasdigital-2 (section 12); commits on other networks
  (testnets) carry no weight.

## 4. Stored commit

| Field | Type | Set by | Description |
|---|---|---|---|
| `id` | uint64 | module | Sequential, first commit has id 1. |
| `version` | uint32 | module | Hash protocol version, always 1. |
| `creator` | address (bech32) | MsgCommit | Signer of the commit. |
| `hash` | 32 bytes | MsgCommit | The commitment. |
| `schema` | string | MsgCommit | Public payload format name. |
| `label` | string | MsgCommit | Optional public text. |
| `commit_height` | int64 | module | Block height of the commit. |
| `commit_time` | timestamp | module | Block time of the commit. |
| `revealed` | bool | module | True after a successful reveal. |
| `revealer` | address | MsgReveal | Empty until revealed. |
| `salt` | 32 bytes | MsgReveal | Empty until revealed. |
| `payload` | bytes | MsgReveal | Empty until revealed. |
| `reveal_height` | int64 | module | 0 until revealed. |
| `reveal_time` | timestamp | module | Unset (null) until revealed. |

A commit is never deleted or modified, except for the one-time transition to
revealed.

## 5. Messages

### 5.1 MsgCommit

`MsgCommit { creator, hash, schema, label }`. The signer is `creator`.
Response: `MsgCommitResponse { id }`.

The message MUST be rejected unless all of the following hold:
1. `creator` is a valid `medas` address whose bytes are 20 or 32 bytes long.
2. `hash` is exactly 32 bytes.
3. `schema` is 1–64 bytes and consists only of `[a-z0-9._-]`.
4. `label` is valid UTF-8 and at most `params.max_label_length` bytes long.
   It may be empty.
5. No commit with the same (`creator`, `hash`) exists. The same hash under a
   different creator is allowed; it can only be a copy (3.3).

On success the module assigns the next id, stores the commit with
`version = 1`, `commit_height` and `commit_time` of the current block, and
emits `EventCommitCreated`.

### 5.2 MsgReveal

`MsgReveal { revealer, id, salt, payload }`. The signer is `revealer`, which may
be **any** address. Attribution follows from the commit's `creator`, which is
bound into the hash.

The message MUST be rejected unless all of the following hold:
1. A commit with `id` exists and is not yet revealed.
2. `salt` is exactly 32 bytes.
3. `payload` is 1 to `params.max_payload_bytes` bytes long, using the parameter
   value at the time of the reveal (see 13.1).
4. `SHA-256(preimage(commit.creator, salt, payload)) == commit.hash`.

There is no deadline for revealing. On success the module sets `revealed`,
`revealer`, `salt`, `payload`, `reveal_height` and `reveal_time` and emits
`EventCommitRevealed`.

Once broadcast, a reveal transaction exposes salt and payload in the mempool.
Anyone can submit the same reveal first. The result is the same except for the
`revealer` field, which is why `revealer` MUST NOT be interpreted as authorship.

### 5.3 MsgUpdateParams

Unchanged: governance-gated update of all parameters (section 6).

## 6. Parameters

| Parameter | Type | Default | Allowed |
|---|---|---|---|
| `max_payload_bytes` | uint32 | 16384 | 1 – 65536 |
| `max_label_length` | uint32 | 128 | 0 – 1024 (0 = labels disabled) |

## 7. State layout

All state lives in the store `medasdigital` and uses `cosmossdk.io/collections`.
The existing parameter key is kept unchanged. The new prefixes are single bytes
below `0x70` (`p`), so none of them is a prefix of `p_medasdigital` and vice versa.

| Prefix | Name | Type | Key → value |
|---|---|---|---|
| `p_medasdigital` (raw key) | Params | item | → `Params` |
| `0x01` | CommitSeq | sequence | → next id (starts at 1, see 11) |
| `0x02` | Commits | map | `uint64 id` → `Commit` |
| `0x03` | HashIndex | map | `Pair[hash bytes, creator address bytes]` → `uint64 id` |
| `0x04` | CreatorIndex | key set | `Pair[creator address bytes, uint64 id]` |

- `HashIndex` enforces rule 5.1.5 and serves `CommitsByHash` through a prefix
  scan on the hash.
- `CreatorIndex` serves `CommitsByCreator` in id order.

## 8. Queries

gRPC service `medasdigital.medasdigital.Query`. REST paths are under
`/medasdigital/medasdigital/`. Hashes are passed as 64 hex characters,
case-insensitive; the module outputs lowercase.

| RPC | REST | module_query_safe |
|---|---|---|
| `Params` | `GET params` | yes |
| `Commit(id)` | `GET commits/{id}` | yes |
| `Commits(pagination)` | `GET commits` | no |
| `CommitsByHash(hash, pagination)` | `GET commits/by_hash/{hash}` | no |
| `CommitsByCreator(creator, pagination)` | `GET commits/by_creator/{creator}` | no |

- `module_query_safe` marks queries that are deterministic and gas-bounded. Such
  queries may be called from other modules, from interchain accounts
  (ICA host `MsgModuleQuerySafe`) and, once enabled, from CosmWasm contracts. The
  response size of `Commit` is bounded by `max_payload_bytes` plus
  `max_label_length`. Paginated queries are not marked.
- All queries are also available through AutoCLI (`medasdigitald q medasdigital …`).

## 9. Events

Typed protobuf events (`EmitTypedEvent`):

```
medasdigital.medasdigital.EventCommitCreated  { id, creator, hash_hex, schema }
medasdigital.medasdigital.EventCommitRevealed { id, creator, revealer }
```

`hash_hex` is lowercase hex.

## 10. Signing

- `MsgCommit` and `MsgReveal` support SIGN_MODE_DIRECT and
  SIGN_MODE_LEGACY_AMINO_JSON (Keplr, Ledger).
- Their amino names are `medasdigital/MsgCommit` and `medasdigital/MsgReveal`,
  within the 39-character limit.
- In amino JSON, byte fields (`hash`, `salt`, `payload`) appear base64-encoded,
  so hardware wallets cannot display the payload in readable form.

## 11. Genesis

`GenesisState { params, commits, next_commit_id }`.

- Export writes all commits in id order and the next id. `next_commit_id` is 1
  on a fresh chain.
- Import MUST reject the genesis unless all of the following hold:
  - params are valid;
  - ids are unique and > 0, and `next_commit_id` > every id;
  - every commit satisfies the stateless rules of 5.1 (and of 5.2 if revealed);
  - no (creator, hash) pair repeats;
  - each revealed commit's salt and payload reproduce its hash.
- `HashIndex` and `CreatorIndex` are not exported; they are rebuilt from the
  commits on import.

## 12. Evaluation rules (normative for interpreting notary data)

These rules define how notary records are to be interpreted. The chain does not
enforce them.

1. **Only revealed commits establish priority.** Priority is determined by
   `commit_height` and `commit_time` of the revealed commit, not by the reveal.
   For commits in the same block, see open point 13.4.
2. **Copies are worthless.** A commit whose hash does not match its creator can
   never be revealed and therefore never establishes anything.
3. **Evaluate an address as a whole.** A prediction MUST be evaluated in the
   context of **all** commits of its creator, including the unrevealed ones.
   `CommitsByCreator` returns them all. This keeps the strategy "commit many
   variants, reveal the one that turned out right" visible: many unrevealed
   commits with the same schema around the same time are evidence of it.
4. **Timestamps are block time.** This is the BFT time of the validator set of
   medasdigital-2. It is as trustworthy as that validator set. Anchoring to
   external timestamping services is planned but not part of this module.
5. **Public and permanent.** Schema and label are public from the commit on.
   The payload is public and cannot be deleted after the reveal. Payloads and
   labels MUST NOT contain personal data.
6. **The salt is the only key.** Whoever loses the salt can never reveal. There
   is no recovery.

## 13. Open points (not normative, to be decided before mainnet)

1. **Lowering `max_payload_bytes` can make commits unrevealable.** Suppose a
   creator commits to a 16 KiB payload and governance then lowers the limit.
   That commit can never be revealed. Options:
   - store the limit in effect at commit time in the commit and check against
     it at reveal; or
   - allow governance only to raise the limit.
2. **Protocol version is not selectable.** `MsgCommit` has no `version` field, so
   a future hash version 2 would need a message change. A `version` field
   (currently required to be 1) could be added now at no cost.
3. **Schema is not bound to the hash.** `schema` and `label` are public claims made
   at commit time and are not covered by the hash. A creator can commit under
   schema A and reveal a payload of another kind. Options:
   - include `schema` in the preimage while the protocol is still unreleased; or
   - require payloads to carry their own schema field (3.2).
4. **Ordering within a block.** Several commits in the same block share
   `commit_height` and `commit_time`. Either they count as simultaneous, or ties
   are broken by `id` (the transaction order chosen by the block proposer).
5. **Label content.** Valid UTF-8 still allows control characters and
   bidirectional overrides (e.g. U+202E), which can make labels look misleading
   in explorers. Consider rejecting Unicode categories Cc and the bidi controls.
6. **Cost and state growth.** Commits are permanent and cost only transaction
   fees. A 16 KiB reveal costs roughly 0.5–0.7 M gas, about 0.016 MEDAS at
   0.025 umedas/gas. Unrevealed commits are never pruned.

## 14. Example

Creator `medas10d07y265gmmuvt4z0w9aw880jnsr700jl30dxf` (test vector 1).

1. Prepare the payload as canonical JSON:
   ```
   {"epoch":"2026-10-01T00:00:00Z","object":"2024 YR4","ra_deg":"123.456789","schema":"orbit.prediction.v1"}
   ```
2. Generate a salt: `scripts/notary_hash.py salt`. The example uses
   `000102…1e1f` for reproducibility; never use a predictable salt in practice.
3. Compute the hash:
   ```
   scripts/notary_hash.py hash --creator medas10d07y265gmmuvt4z0w9aw880jnsr700jl30dxf \
     --salt 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f \
     --payload-file prediction.json
   dfa7416689de1848783c4494b7a4296e1c770d9c80454bcc1a4eb725d3691f6c
   ```
4. Commit. Only the hash, schema and label become public. The response contains the id.
   ```
   medasdigitald tx medasdigital commit \
     --hash dfa7416689de1848783c4494b7a4296e1c770d9c80454bcc1a4eb725d3691f6c \
     --schema orbit.prediction.v1 --label "2024 YR4 close approach" --from <creator>
   ```
   The chain records e.g. `id = 1`, `commit_height = 1200000` and
   `commit_time = 2026-09-30T12:00:00Z`.
5. Keep payload and salt private until the event has happened.
6. Reveal. This can be done by any address, e.g. an institute's archive account.
   ```
   medasdigitald tx medasdigital reveal --id 1 \
     --salt 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f \
     --payload $(xxd -p -c0 prediction.json) --from <any address>
   ```
7. Verify. Anyone can fetch commit 1 and recompute the hash from `creator`,
   `salt` and `payload` with the reference script. The prediction is then proven
   to have been fixed by the creator at `commit_time`. Per rule 12.3, it is
   evaluated together with all other commits of that creator.

(The CLI flags are generated by AutoCLI and may change.)

## 15. Test vectors

Full data, including the preimages and three negative cases, is in the test data
file. Verify it with `scripts/notary_hash.py vectors`.

| # | Creator | Salt (hex) | Payload | Hash (hex) |
|---|---|---|---|---|
| 1 | `medas10d07y265gmmuvt4z0w9aw880jnsr700jl30dxf` (20 bytes, gov module account) | `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` | `{"epoch":"2026-10-01T00:00:00Z","object":"2024 YR4","ra_deg":"123.456789","schema":"orbit.prediction.v1"}` | `dfa7416689de1848783c4494b7a4296e1c770d9c80454bcc1a4eb725d3691f6c` |
| 2 | `medas14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s32jrf6` (32 bytes, CosmWasm contract code 1 / instance 1) | `6d3479a290dce3001d82da753592bccac6719c722dc232de68d34ea41b057dd4` | `{"note":"Δt ≤ 0.5 s, Beobachter: Sternwarte Göttingen","object":"(3200) Phaethon","observer":"Müller"}` (UTF-8) | `7872919d266a32f56ebac8caeb01dc5f342bbaddf1e76f2424beba5099c402e4` |
| 3 | `medas1qyqszqgpqyqszqgpqyqszqgpqyqszqgphqakax` (20 × 0x01) | `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` | `x` (1 byte) | `6020c7c8631884517e1ecf7cb09b8c074c8049b6087e209e542fd35cca61c74f` |
| 4 | as #1 | as #1 | hex `00fffe00` (not UTF-8) | `b3dcd22c5d8366d75e2edce66edb0a1b96e9e44bf89ce9c32da8583f1bb3cb27` |

The vectors were cross-checked independently:
- address bytes with `medasdigitald debug addr`;
- the contract address with wasmd `BuildContractAddressClassic`;
- the hashes with `sha256sum` over a preimage assembled in the shell.
