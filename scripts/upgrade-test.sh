#!/usr/bin/env bash
#
# End-to-end rehearsal of the "v2" software upgrade on the local testnet.
#
# Old binary: the mainnet binary binaries/v1.0.1/medasdigitald. Like on the
# validators it loads libwasmvm (v2.1.2) dynamically from a "system" library
# path; here that is .localnet/syslib via LD_LIBRARY_PATH, because /lib must
# not be touched. New binary: the static release build (make build-release),
# which must not load that library at all. The library stays in place during
# the switch, exactly as on mainnet.
#
#   1. fresh localnet with the old binary; create state: bank, wasm (store,
#      instantiate, query), x/group (group, policy, proposal, vote),
#      tokenfactory denom
#   2. MsgSoftwareUpgrade gov proposal, deposit, vote, wait until passed
#   3. wait for the "UPGRADE NEEDED" halt; snapshot state at the last height
#   4. restart the same home with the new binary (manual swap, no Cosmovisor)
#   5. verify: upgrade applied, same state at the last pre-upgrade height,
#      module versions, libwasmvm versions and loading, wasm query/execute
#      and new upload, group proposal execution, distribution withdrawal,
#      tokenfactory update, a gov proposal, bank send
#   6. genesis export and validate-genesis, restart
#
# Wipes ./.localnet. The node keeps running afterwards
# (stop: scripts/localnet.sh stop).
#
# Environment:
#   UPGRADE_NAME     plan name (default v2)
#   UPGRADE_BUFFER   blocks between proposal and upgrade height (default 100)
#   OLD_BINARY       default binaries/v1.0.1/medasdigitald (mainnet)
#   NEW_BINARY       default build/release/medasdigitald (static)
#   SKIP_BUILD=1     do not run `make build-release`
#   WASM_FILE        test contract (default hackatom.wasm from wasmd testdata)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLD_BINARY="${OLD_BINARY:-$REPO_ROOT/binaries/v1.0.1/medasdigitald}"
NEW_BINARY="${NEW_BINARY:-$REPO_ROOT/build/release/medasdigitald}"
UPGRADE_NAME="${UPGRADE_NAME:-v2}"
UPGRADE_BUFFER="${UPGRADE_BUFFER:-100}"
OLD_WASMVM="2.1.2"
NEW_WASMVM="2.2.9"
# sha256 of the official wasmvm v2.1.2 libwasmvm.x86_64.so = the file on the validators
OLD_LIBWASMVM_SHA256="015bdae5e70304f1e487981f90e3956754718fe7bdac4446aab0838fcb8b33e0"
GOMODCACHE="${GOMODCACHE:-$(go env GOMODCACHE 2>/dev/null || echo "$HOME/go/pkg/mod")}"
OLD_LIBWASMVM_SRC="${OLD_LIBWASMVM_SRC:-$GOMODCACHE/github.com/!cosm!wasm/wasmvm/v2@v$OLD_WASMVM/internal/api/libwasmvm.x86_64.so}"
WASM_FILE="${WASM_FILE:-$GOMODCACHE/github.com/!cosm!wasm/wasmd@v0.54.10/x/wasm/keeper/testdata/hackatom.wasm}"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
	make -C "$REPO_ROOT" build-release
fi

BINARY="$OLD_BINARY"
# shellcheck source=scripts/localnet.sh
source "$REPO_ROOT/scripts/localnet.sh"

SYSLIB="$LOCALNET_DIR/syslib"
MV_BEFORE="$LOCALNET_DIR/module-versions-before.json"
MV_AFTER="$LOCALNET_DIR/module-versions-after.json"
PROPOSAL_FILE="$LOCALNET_DIR/upgrade-proposal.json"
EXPORT_FILE="$LOCALNET_DIR/export-after-upgrade.json"

# Fixed gas: --gas auto underestimates MsgVote (out of gas at WritePerByte).
tx_flags=(--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE"
	--gas 400000 --fees "10000$DENOM" --yes --output json)
wasm_flags=(--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE"
	--gas 5000000 --fees "125000$DENOM" --yes --output json)

q() { bin query "$@" --node "$NODE" --output json; }

module_versions() {
	q upgrade module-versions | jq -S '[.module_versions[] | {(.name): ((.version // "0") | tonumber)}] | add'
}

proposal_status() {
	q gov proposal "$1" | jq -r '.proposal.status // .status'
}

log_since_last_start() {
	awk '/^===== .* starting /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$LOG_FILE"
}

# Last height committed by the app. After an upgrade halt CometBFT's
# /status already reports the upgrade height (the block is stored before the
# app executes it), while the app is one block behind.
app_height() {
	curl -sf "http://127.0.0.1:$RPC_PORT/abci_info" | jq -r '.result.response.last_block_height'
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' | cut -c1-200; }

step() { echo; echo "######## $*"; }

# Value of an event attribute in an included tx (typed events are JSON-quoted).
event_attr() { # tx json, event type, attribute key
	echo "$1" | jq -r --arg t "$2" --arg k "$3" \
		'[.events[] | select(.type == $t) | .attributes[] | select(.key == $k) | .value][0] | ltrimstr("\"") | rtrimstr("\"")'
}

sha256() { sha256sum "$1" | cut -d' ' -f1; }

# libwasmvm mappings of the running node process.
node_libwasmvm() { grep -o '/[^ ]*libwasmvm[^ ]*' "/proc/$(node_pid)/maps" 2>/dev/null | sort -u || true; }

balance_of() { q bank balance "$1" "$DENOM" | jq -r '.balance.amount'; }

# Deterministic view of the test state at a given height.
state_snapshot() { # height
	local h="$1" out="{}" a
	for k in "$VALIDATOR_KEY" alice bob; do
		a="$(addr "$k")"
		out="$(echo "$out" | jq --arg k "$k" --argjson v "$(q bank balances "$a" --height "$h" | jq -c .balances)" '.[$k] = $v')"
	done
	out="$(echo "$out" | jq --argjson v "$(q bank balances "$CONTRACT" --height "$h" | jq -c .balances)" '.contract = $v')"
	out="$(echo "$out" | jq --argjson v "$(q bank balances "$POLICY" --height "$h" | jq -c .balances)" '.group_policy = $v')"
	out="$(echo "$out" | jq --argjson v "$(q wasm contract-state smart "$CONTRACT" '{"verifier":{}}' --height "$h" | jq -c .data)" '.contract_query = $v')"
	out="$(echo "$out" | jq --argjson v "$(q tokenfactory show-denom "$TF_DENOM" --height "$h" | jq -c .)" '.tokenfactory = $v')"
	out="$(echo "$out" | jq --argjson v "$(q group proposal "$GROUP_PROPOSAL" --height "$h" | jq -c '.proposal | {status, final_tally_result}')" '.group_proposal = $v')"
	out="$(echo "$out" | jq --argjson v "$(q bank total --height "$h" | jq -c .supply)" '.supply = $v')"
	echo "$out" | jq -S .
}

tx() { # tx args... -> included tx JSON (fails on any error)
	wait_tx "$(bin tx "$@" "${tx_flags[@]}")"
}

# ------------------------------------------------------------------ binaries
step "0/6 binaries and system library"
[ -x "$OLD_BINARY" ] || die "old binary missing: $OLD_BINARY"
[ -x "$NEW_BINARY" ] || die "new binary missing: $NEW_BINARY (make build-release)"
[ -f "$WASM_FILE" ] || die "wasm file missing: $WASM_FILE"
readelf -d "$NEW_BINARY" 2>&1 | grep -q "no dynamic section" || die "new binary is not statically linked"
log "old: $OLD_BINARY sha256 $(sha256 "$OLD_BINARY")"
log "new: $NEW_BINARY sha256 $(sha256 "$NEW_BINARY") (static)"

require_tools
stop_node
wipe_localnet
mkdir -p "$SYSLIB"
cp "$OLD_LIBWASMVM_SRC" "$SYSLIB/libwasmvm.x86_64.so"
[ "$(sha256 "$SYSLIB/libwasmvm.x86_64.so")" = "$OLD_LIBWASMVM_SHA256" ] || die "libwasmvm $OLD_WASMVM checksum mismatch"
export LD_LIBRARY_PATH="$SYSLIB"
log "system library: $SYSLIB/libwasmvm.x86_64.so ($OLD_WASMVM, sha256 $OLD_LIBWASMVM_SHA256)"

# ----------------------------------------------------------- old: create state
step "1/6 fresh localnet with OLD binary ($("$OLD_BINARY" version --home "$HOME_DIR")), create state"
init_chain
start_node
wait_for_blocks 3
loaded="$(node_libwasmvm)"
[ "$loaded" = "$SYSLIB/libwasmvm.x86_64.so" ] || die "old node loads libwasmvm from '$loaded'"
log "old node loads $loaded"
v="$(bin query wasm libwasmvm-version)"
[ "$v" = "$OLD_WASMVM" ] || die "old libwasmvm-version $v"
log "libwasmvm-version (old): $v"
smoke_test

ALICE="$(addr alice)"
BOB="$(addr bob)"
VALOPER="$(bin keys show "$VALIDATOR_KEY" --bech val -a --keyring-backend "$KEYRING")"

# wasm: store, instantiate with funds, query
t="$(wait_tx "$(bin tx wasm store "$WASM_FILE" --from alice "${wasm_flags[@]}")")"
CODE_ID="$(event_attr "$t" store_code code_id)"
t="$(wait_tx "$(bin tx wasm instantiate "$CODE_ID" "{\"verifier\":\"$ALICE\",\"beneficiary\":\"$BOB\"}" \
	--label hackatom-pre-upgrade --no-admin --amount "5000$DENOM" --from alice "${wasm_flags[@]}")")"
CONTRACT="$(event_attr "$t" instantiate _contract_address)"
[ "$(q wasm contract-state smart "$CONTRACT" '{"verifier":{}}' | jq -r .data.verifier)" = "$ALICE" ] || die "contract query failed"
log "wasm: code $CODE_ID, contract $CONTRACT holds $(balance_of "$CONTRACT")$DENOM, query verifier ok"

# x/group: group with policy, fund the policy, proposal, vote (executed after the upgrade)
jq -n --arg a "$ALICE" --arg b "$BOB" '{members: [{address: $a, weight: "1", metadata: "alice"}, {address: $b, weight: "1", metadata: "bob"}]}' >"$LOCALNET_DIR/group-members.json"
jq -n '{"@type": "/cosmos.group.v1.ThresholdDecisionPolicy", threshold: "1", windows: {voting_period: "15s", min_execution_period: "0s"}}' >"$LOCALNET_DIR/group-policy.json"
t="$(tx group create-group-with-policy "$ALICE" "test group" "test policy" "$LOCALNET_DIR/group-members.json" "$LOCALNET_DIR/group-policy.json" --group-policy-as-admin --from alice)"
POLICY="$(event_attr "$t" cosmos.group.v1.EventCreateGroupPolicy address)"
tx bank send alice "$POLICY" "1000000$DENOM" >/dev/null
jq -n --arg p "$POLICY" --arg a "$ALICE" --arg b "$BOB" --arg d "$DENOM" '{
	group_policy_address: $p,
	messages: [{"@type": "/cosmos.bank.v1beta1.MsgSend", from_address: $p, to_address: $b, amount: [{denom: $d, amount: "777"}]}],
	metadata: "", proposers: [$a], title: "pay bob", summary: "group proposal across the upgrade"
}' >"$LOCALNET_DIR/group-proposal.json"
t="$(tx group submit-proposal "$LOCALNET_DIR/group-proposal.json" --from alice)"
GROUP_PROPOSAL="$(event_attr "$t" cosmos.group.v1.EventSubmitProposal proposal_id)"
tx group vote "$GROUP_PROPOSAL" "$ALICE" VOTE_OPTION_YES "" --from alice >/dev/null
log "group: policy $POLICY, proposal $GROUP_PROPOSAL voted yes (to be executed after the upgrade)"

# tokenfactory
TF_DENOM="utest"
tx tokenfactory create-denom "$TF_DENOM" "Test token" TST 6 https://example.org 1000000 1000 true --from alice >/dev/null
log "tokenfactory: $(q tokenfactory show-denom "$TF_DENOM" | jq -c '.denom | {denom, owner, supply, maxSupply}')"

module_versions >"$MV_BEFORE"
log "module versions before: $(jq -c . "$MV_BEFORE")"

# ------------------------------------------------------------------ proposal
step "2/6 governance proposal for upgrade \"$UPGRADE_NAME\""
authority="$(q upgrade authority | jq -r '.address')"
deposit="$(q gov params | jq -r '(.params // .deposit_params).min_deposit[0] | .amount + .denom')"
upgrade_height=$(($(height) + UPGRADE_BUFFER))
jq -n --arg auth "$authority" --arg name "$UPGRADE_NAME" --arg h "$upgrade_height" --arg dep "$deposit" '{
	messages: [{"@type": "/cosmos.upgrade.v1beta1.MsgSoftwareUpgrade", authority: $auth, plan: {name: $name, height: $h, info: ""}}],
	metadata: "", deposit: $dep, title: ("Software upgrade " + $name),
	summary: ("Localnet rehearsal of the " + $name + " upgrade"), expedited: false
}' >"$PROPOSAL_FILE"
t="$(tx gov submit-proposal "$PROPOSAL_FILE" --from "$VALIDATOR_KEY")"
proposal_id="$(event_attr "$t" submit_proposal proposal_id)"
tx gov vote "$proposal_id" yes --from "$VALIDATOR_KEY" >/dev/null
log "proposal $proposal_id for height $upgrade_height submitted and voted, waiting for the voting period"
for _ in $(seq 1 120); do
	status="$(proposal_status "$proposal_id")"
	case "$status" in
	PROPOSAL_STATUS_PASSED) break ;;
	PROPOSAL_STATUS_REJECTED | PROPOSAL_STATUS_FAILED) die "proposal $proposal_id: $status" ;;
	esac
	sleep 2
done
[ "$status" = "PROPOSAL_STATUS_PASSED" ] || die "proposal $proposal_id not passed ($status)"
[ "$(height)" -lt "$upgrade_height" ] || die "proposal passed after the upgrade height (increase UPGRADE_BUFFER)"
log "proposal passed at height $(height); plan $(q upgrade plan | jq -c '.plan | {name, height}')"

# ---------------------------------------------------------------------- halt
step "3/6 waiting for the OLD binary to halt at height $upgrade_height"
needed_msg="UPGRADE \"$UPGRADE_NAME\" NEEDED at height: $upgrade_height"
for _ in $(seq 1 $((UPGRADE_BUFFER * 3 + 60))); do
	grep -qF "$needed_msg" "$LOG_FILE" && break
	sleep 1
done
grep -qF "$needed_msg" "$LOG_FILE" || die "old binary did not report '$needed_msg', see $LOG_FILE"
log "log: $(grep -F "$needed_msg" "$LOG_FILE" | head -1 | strip_ansi)"
sleep 3
last_height="$(app_height)"
[ "$last_height" -eq $((upgrade_height - 1)) ] || die "expected app halted at $((upgrade_height - 1)), app height is $last_height"
log "chain halted: app height $last_height, block store height $(height)"
state_snapshot "$last_height" >"$LOCALNET_DIR/state-old.json"
log "state at height $last_height recorded with the old binary"
cache_before="$(find "$HOME_DIR/wasm" -maxdepth 4 -type d | sed "s|$HOME_DIR/||" | sort | tr '\n' ' ')"
stop_node

# ---------------------------------------------------------------- new binary
step "4/6 restarting with NEW binary ($("$NEW_BINARY" version --home "$HOME_DIR")), library left in place"
BINARY="$NEW_BINARY"
start_node
wait_for_blocks $((upgrade_height + 3))
new_log="$(log_since_last_start)"
echo "$new_log" | grep -qF "applying upgrade \"$UPGRADE_NAME\" at height: $upgrade_height" || die "no 'applying upgrade' log line"
log "log: $(echo "$new_log" | grep -F "applying upgrade" | head -1 | strip_ansi)"
log "log: $(echo "$new_log" | grep -F "running upgrade handler" | head -1 | strip_ansi)"
if echo "$new_log" | grep -E " (ERR|ERROR) |panic" | grep -v "grpc\|p2p\|pex" | strip_ansi | head -5 | grep .; then
	die "errors in the new binary's log"
fi
[ -z "$(node_libwasmvm)" ] || die "new node maps a libwasmvm: $(node_libwasmvm)"
[ "$(sha256 "$SYSLIB/libwasmvm.x86_64.so")" = "$OLD_LIBWASMVM_SHA256" ] || die "system library changed"
log "new node maps no libwasmvm; system library untouched (sha256 unchanged)"

# ------------------------------------------------------------------- verify
step "5/6 verification"
applied="$(q upgrade applied "$UPGRADE_NAME" | jq -r '.height')"
[ "$applied" = "$upgrade_height" ] || die "query upgrade applied: $applied, expected $upgrade_height"
log "query upgrade applied $UPGRADE_NAME: height $applied"

state_snapshot "$last_height" >"$LOCALNET_DIR/state-new.json"
diff "$LOCALNET_DIR/state-old.json" "$LOCALNET_DIR/state-new.json" || die "state at height $last_height differs between old and new binary"
log "state at height $last_height identical via old and new binary (balances, supply, contract, group, tokenfactory)"

module_versions >"$MV_AFTER"
diff <(jq -S . "$MV_BEFORE") <(jq -S . "$MV_AFTER") || die "module versions changed (no dependency brings a migration)"
log "module versions unchanged ($(jq length "$MV_AFTER") modules)"

v="$(bin query wasm libwasmvm-version)"
[ "$v" = "$NEW_WASMVM" ] || die "new libwasmvm-version $v"
log "libwasmvm-version (new): $v"
log "wasm cache dirs before: $cache_before"
log "wasm cache dirs after:  $(find "$HOME_DIR/wasm" -maxdepth 4 -type d | sed "s|$HOME_DIR/||" | sort | tr '\n' ' ')"

# wasm: query and execute the pre-upgrade contract, store and instantiate anew
[ "$(q wasm contract-state smart "$CONTRACT" '{"verifier":{}}' | jq -r .data.verifier)" = "$ALICE" ] || die "contract query after upgrade failed"
bob_before="$(balance_of "$BOB")"
wait_tx "$(bin tx wasm execute "$CONTRACT" '{"release":{}}' --from alice "${wasm_flags[@]}")" >/dev/null
[ "$(balance_of "$BOB")" -eq $((bob_before + 5000)) ] || die "contract release did not pay bob"
t="$(wait_tx "$(bin tx wasm store "$WASM_FILE" --from alice "${wasm_flags[@]}")")"
code2="$(event_attr "$t" store_code code_id)"
t="$(wait_tx "$(bin tx wasm instantiate "$code2" "{\"verifier\":\"$ALICE\",\"beneficiary\":\"$BOB\"}" --label hackatom-post-upgrade --no-admin --from bob "${wasm_flags[@]}")")"
log "wasm: old contract query + execute (release paid bob 5000) ok; new code $code2 instantiated at $(event_attr "$t" instantiate _contract_address)"

# x/group: execute the pre-upgrade proposal
bob_before="$(balance_of "$BOB")"
t="$(tx group exec "$GROUP_PROPOSAL" --from alice)"
result="$(event_attr "$t" cosmos.group.v1.EventExec result)"
[ "$result" = "PROPOSAL_EXECUTOR_RESULT_SUCCESS" ] || die "group exec result $result"
[ "$(balance_of "$BOB")" -eq $((bob_before + 777)) ] || die "group proposal did not pay bob"
log "group: proposal $GROUP_PROPOSAL executed ($result), bob +777"

# distribution: rewards and commission
t="$(tx distribution withdraw-rewards "$VALOPER" --commission --from "$VALIDATOR_KEY")"
rewards="$(event_attr "$t" withdraw_rewards amount)"
commission="$(event_attr "$t" withdraw_commission amount)"
[ -n "$rewards" ] && [ "$rewards" != "null" ] && [ -n "$commission" ] && [ "$commission" != "null" ] || die "withdrawal without rewards/commission"
log "distribution: withdrew rewards $rewards and commission $commission"

# tokenfactory: denom unchanged (checked in the snapshot), owner can update
tx tokenfactory update-denom "$TF_DENOM" "Test token (post upgrade)" TST 6 https://example.org 2000000 1000 true --from alice >/dev/null
[ "$(q tokenfactory show-denom "$TF_DENOM" | jq -r .denom.maxSupply)" = "2000000" ] || die "tokenfactory update failed"
log "tokenfactory: update-denom by owner ok"

# gov: a text proposal passes
jq -n '{messages: [], metadata: "post-upgrade governance check", deposit: "10000000umedas", title: "Post-upgrade text proposal", summary: "Checks governance after the upgrade", expedited: false}' >"$LOCALNET_DIR/text-proposal.json"
t="$(tx gov submit-proposal "$LOCALNET_DIR/text-proposal.json" --from "$VALIDATOR_KEY")"
pid="$(event_attr "$t" submit_proposal proposal_id)"
tx gov vote "$pid" yes --from "$VALIDATOR_KEY" >/dev/null
for _ in $(seq 1 60); do [ "$(proposal_status "$pid")" = PROPOSAL_STATUS_PASSED ] && break; sleep 2; done
[ "$(proposal_status "$pid")" = PROPOSAL_STATUS_PASSED ] || die "post-upgrade gov proposal $pid: $(proposal_status "$pid")"
log "gov: proposal $pid passed"

smoke_test

# ------------------------------------------------------------ genesis export
step "6/6 genesis export and validate-genesis"
stop_node
bin export --output-document "$EXPORT_FILE" >/dev/null 2>&1
bin genesis validate "$EXPORT_FILE" >/dev/null
log "exported at height $(jq -r .initial_height "$EXPORT_FILE") ($(du -h "$EXPORT_FILE" | cut -f1)), genesis validate ok"
start_node
wait_for_new_blocks 2

echo
echo "========================================================================"
echo " UPGRADE TEST PASSED: \"$UPGRADE_NAME\" applied at height $upgrade_height"
echo " old: $("$OLD_BINARY" version --home "$HOME_DIR") (libwasmvm $OLD_WASMVM from $SYSLIB)"
echo " new: $("$NEW_BINARY" version --home "$HOME_DIR") (static, libwasmvm $NEW_WASMVM)"
echo " node keeps running (height $(height)); stop with: scripts/localnet.sh stop"
echo "========================================================================"
