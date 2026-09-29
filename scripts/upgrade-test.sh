#!/usr/bin/env bash
#
# End-to-end software upgrade rehearsal on the local testnet.
#
#   1. build build/old (OLD_REF, default = mainnet v1.0.1 code) and build/new
#      (current checkout) via `make build-upgrade-binaries`
#   2. start a fresh localnet with the old binary, bank-send smoke test
#   3. submit a MsgSoftwareUpgrade gov proposal for UPGRADE_NAME at
#      current height + UPGRADE_BUFFER, deposit, vote yes, wait until passed
#   4. wait until the old binary halts with "UPGRADE ... NEEDED"
#   5. restart the same home with the new binary (manual swap, no Cosmovisor)
#   6. verify: blocks continue, `query upgrade applied` returns the upgrade
#      height, module versions are as expected, bank-send smoke test
#
# Uses scripts/localnet.sh (sourced) and wipes ./.localnet. The node keeps
# running afterwards; stop it with `scripts/localnet.sh stop`.
#
# Environment:
#   UPGRADE_NAME    plan name (default v2)
#   UPGRADE_BUFFER  blocks between proposal and upgrade height (default 100;
#                   must cover the 60s voting period at ~1s block time)
#   SKIP_BUILD=1    use existing build/old and build/new binaries

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLD_BINARY="$REPO_ROOT/build/old/medasdigitald"
NEW_BINARY="$REPO_ROOT/build/new/medasdigitald"
UPGRADE_NAME="${UPGRADE_NAME:-v2}"
UPGRADE_BUFFER="${UPGRADE_BUFFER:-100}"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
	make -C "$REPO_ROOT" build-upgrade-binaries
fi

BINARY="$OLD_BINARY"
# shellcheck source=scripts/localnet.sh
source "$REPO_ROOT/scripts/localnet.sh"

MV_BEFORE="$LOCALNET_DIR/module-versions-before.json"
MV_AFTER="$LOCALNET_DIR/module-versions-after.json"
PROPOSAL_FILE="$LOCALNET_DIR/upgrade-proposal.json"

# Fixed gas: --gas auto underestimates MsgVote (out of gas at WritePerByte).
tx_flags=(--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE"
	--gas 400000 --fees "10000$DENOM" --yes --output json)

module_versions() {
	bin query upgrade module-versions --node "$NODE" --output json |
		jq -S '[.module_versions[] | {(.name): ((.version // "0") | tonumber)}] | add'
}

proposal_status() {
	bin query gov proposal "$1" --node "$NODE" --output json | jq -r '.proposal.status // .status'
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

# ---------------------------------------------------------------- old binary
step "1/5 fresh localnet with OLD binary ($("$OLD_BINARY" version --home "$HOME_DIR"))"
require_tools
[ -x "$NEW_BINARY" ] || die "new binary missing at $NEW_BINARY"
stop_node
wipe_localnet
init_chain
start_node
wait_for_blocks 3
smoke_test
module_versions >"$MV_BEFORE"
log "module versions before: $(jq -c . "$MV_BEFORE")"

# ------------------------------------------------------------------ proposal
step "2/5 governance proposal for upgrade \"$UPGRADE_NAME\""
authority="$(bin query upgrade authority --node "$NODE" --output json | jq -r '.address')"
deposit="$(bin query gov params --node "$NODE" --output json |
	jq -r '(.params // .deposit_params).min_deposit[0] | .amount + .denom')"
upgrade_height=$(($(height) + UPGRADE_BUFFER))

jq -n --arg auth "$authority" --arg name "$UPGRADE_NAME" --arg h "$upgrade_height" --arg dep "$deposit" '{
	messages: [{
		"@type": "/cosmos.upgrade.v1beta1.MsgSoftwareUpgrade",
		authority: $auth,
		plan: {name: $name, height: $h, info: ""}
	}],
	metadata: "",
	deposit: $dep,
	title: ("Software upgrade " + $name),
	summary: ("Localnet rehearsal of the " + $name + " upgrade"),
	expedited: false
}' >"$PROPOSAL_FILE"
log "upgrade height $upgrade_height, deposit $deposit, authority $authority"

res="$(bin tx gov submit-proposal "$PROPOSAL_FILE" --from "$VALIDATOR_KEY" "${tx_flags[@]}")"
tx="$(wait_tx "$res")"
proposal_id="$(echo "$tx" | jq -r '[.events[] | select(.type == "submit_proposal") | .attributes[] | select(.key == "proposal_id") | .value][0]')"
[ -n "$proposal_id" ] && [ "$proposal_id" != "null" ] || die "could not determine proposal id"
log "proposal $proposal_id submitted, status $(proposal_status "$proposal_id")"

res="$(bin tx gov vote "$proposal_id" yes --from "$VALIDATOR_KEY" "${tx_flags[@]}")"
wait_tx "$res" >/dev/null
log "voted yes, waiting for the voting period to end"

for _ in $(seq 1 120); do
	status="$(proposal_status "$proposal_id")"
	case "$status" in
	PROPOSAL_STATUS_PASSED) break ;;
	PROPOSAL_STATUS_REJECTED | PROPOSAL_STATUS_FAILED) die "proposal $proposal_id: $status" ;;
	esac
	sleep 2
done
[ "$status" = "PROPOSAL_STATUS_PASSED" ] || die "proposal $proposal_id not passed after 240s ($status)"
h="$(height)"
[ "$h" -lt "$upgrade_height" ] || die "proposal passed at height $h, after the upgrade height (increase UPGRADE_BUFFER)"
plan="$(bin query upgrade plan --node "$NODE" --output json)"
log "proposal passed at height $h; plan: $(echo "$plan" | jq -c '.plan | {name, height}')"
[ "$(echo "$plan" | jq -r '.plan.name')" = "$UPGRADE_NAME" ] || die "upgrade plan not scheduled"

# ---------------------------------------------------------------------- halt
step "3/5 waiting for the OLD binary to halt at height $upgrade_height"
needed_msg="UPGRADE \"$UPGRADE_NAME\" NEEDED at height: $upgrade_height"
for _ in $(seq 1 $((UPGRADE_BUFFER * 3 + 60))); do
	grep -qF "$needed_msg" "$LOG_FILE" && break
	sleep 1
done
grep -qF "$needed_msg" "$LOG_FILE" || die "old binary did not report '$needed_msg', see $LOG_FILE"
log "log: $(grep -F "$needed_msg" "$LOG_FILE" | head -1 | strip_ansi)"
grep -q "CONSENSUS FAILURE" "$LOG_FILE" && log "log: $(grep -m1 "CONSENSUS FAILURE" "$LOG_FILE" | strip_ansi)"

sleep 3
h="$(app_height)"
[ "$h" -eq $((upgrade_height - 1)) ] || die "expected app halted at $((upgrade_height - 1)), app height is $h"
log "chain halted: app height $h, block store height $(height)"

info_file="$HOME_DIR/data/upgrade-info.json"
[ -f "$info_file" ] || die "$info_file missing"
log "upgrade-info.json: $(jq -c . "$info_file")"
stop_node

# ---------------------------------------------------------------- new binary
step "4/5 restarting with NEW binary ($("$NEW_BINARY" version --home "$HOME_DIR"))"
BINARY="$NEW_BINARY"
start_node
wait_for_blocks $((upgrade_height + 3))

new_log="$(log_since_last_start)"
applying="$(echo "$new_log" | grep -F "applying upgrade \"$UPGRADE_NAME\" at height: $upgrade_height" | head -1)" ||
	die "no 'applying upgrade' line in the new binary's log"
log "log: $(echo "$applying" | strip_ansi)"
handler="$(echo "$new_log" | grep -F "running upgrade handler" | head -1)" ||
	die "upgrade handler did not log"
log "log: $(echo "$handler" | strip_ansi)"

# ------------------------------------------------------------------- verify
step "5/5 verification"
applied="$(bin query upgrade applied "$UPGRADE_NAME" --node "$NODE" --output json | jq -r '.height')"
[ "$applied" = "$upgrade_height" ] || die "query upgrade applied: $applied, expected $upgrade_height"
log "query upgrade applied $UPGRADE_NAME: height $applied"

plan_after="$(bin query upgrade plan --node "$NODE" --output json 2>&1 || true)"
echo "$plan_after" | grep -q '"name"' && die "upgrade plan still set after the upgrade: $plan_after"
log "no pending upgrade plan"

module_versions >"$MV_AFTER"
if ! diff <(jq -S . "$MV_BEFORE") <(jq -S . "$MV_AFTER"); then
	die "module versions changed, but the empty $UPGRADE_NAME upgrade changes no ConsensusVersion"
fi
for m in bank staking gov upgrade ibc transfer wasm medasdigital tokenfactory; do
	jq -e --arg m "$m" 'has($m)' "$MV_AFTER" >/dev/null || die "module $m missing from module versions"
done
log "module versions unchanged ($(jq 'length' "$MV_AFTER") modules), e.g. $(jq -c '{ibc, wasm, medasdigital, tokenfactory}' "$MV_AFTER")"

smoke_test

echo
echo "========================================================================"
echo " UPGRADE TEST PASSED: \"$UPGRADE_NAME\" applied at height $upgrade_height"
echo " old: $("$OLD_BINARY" version --home "$HOME_DIR")  ->  new: $("$NEW_BINARY" version --home "$HOME_DIR")"
echo " node keeps running (height $(height)); stop with: scripts/localnet.sh stop"
echo "========================================================================"
