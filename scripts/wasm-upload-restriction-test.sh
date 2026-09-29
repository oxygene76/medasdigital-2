#!/usr/bin/env bash
#
# Localnet rehearsal of proposals/wasm-upload-restriction.json with the
# mainnet binary (build/old, see `make build-upgrade-binaries`).
#
#   1. fresh localnet (expedited voting period 20s), mainnet-like wasm params
#      (upload and instantiate: Everybody); bob uploads code 1
#   2. localnet copy of the mainnet proposal: only the deploy address is
#      replaced by alice's address; verified by diff
#   3. submit (expedited), vote yes, wait until passed within the expedited
#      period
#   4. verify: wasm params, bob's upload fails, alice's upload succeeds, bob
#      can still instantiate code 1 and alice's new code
#   5. rollback: proposals/wasm-upload-unrestrict.json, bob can upload again
#
# Wipes ./.localnet. The node keeps running afterwards.
#
# Environment: BINARY (default build/old/medasdigitald), WASM_FILE (default
# hackatom.wasm from the wasmd module cache).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/build/old/medasdigitald}"
EXPEDITED_VOTING_PERIOD="${EXPEDITED_VOTING_PERIOD:-20s}"
# shellcheck source=scripts/localnet.sh
source "$REPO_ROOT/scripts/localnet.sh"

MAINNET_PROPOSAL="$REPO_ROOT/proposals/wasm-upload-restriction.json"
ROLLBACK_PROPOSAL="$REPO_ROOT/proposals/wasm-upload-unrestrict.json"
MAINNET_GOV="medas10d07y265gmmuvt4z0w9aw880jnsr700jl30dxf"
MAINNET_DEPLOY="medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv"
GOMODCACHE="${GOMODCACHE:-$(go env GOMODCACHE 2>/dev/null || echo "$HOME/go/pkg/mod")}"
WASM_FILE="${WASM_FILE:-$GOMODCACHE/github.com/!cosm!wasm/wasmd@v0.53.0/x/wasm/keeper/testdata/hackatom.wasm}"
TEST_PROPOSAL="$LOCALNET_DIR/wasm-upload-restriction.localnet.json"

gov_flags=(--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE"
	--gas 400000 --fees "10000$DENOM" --yes --output json)
wasm_flags=(--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE"
	--gas 5000000 --fees "125000$DENOM" --yes --output json)

step() { echo; echo "######## $*"; }
q() { bin query "$@" --node "$NODE" --output json; }

# Broadcast result -> included tx JSON, without failing on a DeliverTx error.
tx_result() {
	local res="$1" hash
	[ "$(echo "$res" | jq -r '.code')" = "0" ] || { echo "$res"; return 0; }
	hash="$(echo "$res" | jq -r '.txhash')"
	for _ in $(seq 1 30); do
		if res="$(q tx "$hash" 2>/dev/null)"; then
			echo "$res"
			return 0
		fi
		sleep 1
	done
	die "tx $hash not found after 30s"
}

event_attr() { # tx json, event type, attribute key
	echo "$1" | jq -r --arg t "$2" --arg k "$3" \
		'[.events[] | select(.type == $t) | .attributes[] | select(.key == $k) | .value][0]'
}

store_code() { # key -> included tx JSON
	tx_result "$(bin tx wasm store "$WASM_FILE" --from "$1" "${wasm_flags[@]}")"
}

instantiate() { # key, code id -> included tx JSON
	local a
	a="$(addr "$1")"
	tx_result "$(bin tx wasm instantiate "$2" "{\"verifier\":\"$a\",\"beneficiary\":\"$a\"}" \
		--label "test-$1-$2" --no-admin --from "$1" "${wasm_flags[@]}")"
}

pass_proposal() { # proposal file, expected expedited (true|false) -> seconds until passed
	local file="$1" expedited="$2" res tx id status t0
	res="$(bin tx gov submit-proposal "$file" --from "$VALIDATOR_KEY" "${gov_flags[@]}")"
	tx="$(wait_tx "$res")"
	id="$(event_attr "$tx" submit_proposal proposal_id)"
	[ "$(q gov proposal "$id" | jq -r '.proposal.expedited // false')" = "$expedited" ] ||
		die "proposal $id: expedited flag is not $expedited"
	t0=$(date +%s)
	log "proposal $id submitted (expedited=$expedited), status $(q gov proposal "$id" | jq -r .proposal.status)" >&2
	wait_tx "$(bin tx gov vote "$id" yes --from "$VALIDATOR_KEY" "${gov_flags[@]}")" >/dev/null
	for _ in $(seq 1 120); do
		status="$(q gov proposal "$id" | jq -r .proposal.status)"
		case "$status" in
		PROPOSAL_STATUS_PASSED) break ;;
		PROPOSAL_STATUS_REJECTED | PROPOSAL_STATUS_FAILED) die "proposal $id: $status ($(q gov proposal "$id" | jq -c .proposal.failed_reason))" ;;
		esac
		sleep 1
	done
	[ "$status" = "PROPOSAL_STATUS_PASSED" ] || die "proposal $id not passed ($status)"
	echo $(($(date +%s) - t0))
}

# --------------------------------------------------------------------- setup
step "1/5 fresh localnet with $("$BINARY" version --home "$HOME_DIR")"
require_tools
[ -f "$WASM_FILE" ] || die "wasm file not found: $WASM_FILE"
stop_node
wipe_localnet
init_chain
start_node
wait_for_blocks 3

gov_params="$(q gov params | jq -c '.params | {voting_period, expedited_voting_period, expedited_min_deposit, expedited_threshold}')"
log "gov params: $gov_params"
[ "$(echo "$gov_params" | jq -r '.expedited_min_deposit[0].amount + .expedited_min_deposit[0].denom')" = "50000000umedas" ] ||
	die "expedited_min_deposit differs from mainnet"
echo "$gov_params" | jq -e '.expedited_threshold | test("^0\\.6670*$")' >/dev/null || die "expedited_threshold differs from mainnet"

wasm_params="$(q wasm params | jq -c '.params // .')"
log "wasm params: $wasm_params"
[ "$(echo "$wasm_params" | jq -r '.code_upload_access.permission + "/" + .instantiate_default_permission')" = "Everybody/Everybody" ] ||
	die "wasm params are not mainnet-like"

gov_addr="$(q auth module-account gov | jq -r '.account.value.address // .account.base_account.address')"
[ "$gov_addr" = "$MAINNET_GOV" ] || die "gov module address $gov_addr differs from mainnet $MAINNET_GOV"
log "gov module address $gov_addr = mainnet"

tx="$(store_code bob)"
[ "$(echo "$tx" | jq -r .code)" = "0" ] || die "initial upload by bob failed: $(echo "$tx" | jq -r .raw_log)"
code_before="$(event_attr "$tx" store_code code_id)"
log "bob uploaded code $code_before before the restriction"

# ------------------------------------------------------------------ proposal
step "2/5 localnet copy of the mainnet proposal"
deployer="$(addr alice)"
jq --arg d "$deployer" '.messages[0].params.code_upload_access.addresses = [$d]' "$MAINNET_PROPOSAL" >"$TEST_PROPOSAL"
if ! diff <(jq -S --arg d "$MAINNET_DEPLOY" '.messages[0].params.code_upload_access.addresses = [$d]' "$TEST_PROPOSAL") \
	<(jq -S . "$MAINNET_PROPOSAL") >/dev/null; then
	die "localnet proposal differs from the mainnet proposal in more than the deploy address"
fi
log "identical to $MAINNET_PROPOSAL except deploy address $MAINNET_DEPLOY -> $deployer (alice)"
diff "$MAINNET_PROPOSAL" "$TEST_PROPOSAL" | sed 's/^/    /' || true

step "3/5 submit, vote, wait (expedited voting period $EXPEDITED_VOTING_PERIOD)"
secs="$(pass_proposal "$TEST_PROPOSAL" true)"
[ "$secs" -lt 60 ] || die "passed after ${secs}s, i.e. not within the expedited period"
log "proposal passed ${secs}s after submission (expedited)"

# -------------------------------------------------------------------- verify
step "4/5 verification"
wasm_params="$(q wasm params | jq -c '.params // .')"
log "wasm params: $wasm_params"
[ "$(echo "$wasm_params" | jq -r '.code_upload_access.permission')" = "AnyOfAddresses" ] || die "upload permission not AnyOfAddresses"
[ "$(echo "$wasm_params" | jq -c '.code_upload_access.addresses')" = "[\"$deployer\"]" ] || die "unexpected upload addresses"
[ "$(echo "$wasm_params" | jq -r '.instantiate_default_permission')" = "Everybody" ] || die "instantiate permission changed"

tx="$(store_code bob)"
[ "$(echo "$tx" | jq -r .code)" != "0" ] || die "upload by bob (not deploy address) succeeded"
log "upload by bob rejected: code $(echo "$tx" | jq -r .code) (codespace $(echo "$tx" | jq -r .codespace)): $(echo "$tx" | jq -r .raw_log)"

tx="$(store_code alice)"
[ "$(echo "$tx" | jq -r .code)" = "0" ] || die "upload by deploy address failed: $(echo "$tx" | jq -r .raw_log)"
code_deployer="$(event_attr "$tx" store_code code_id)"
log "upload by alice (deploy address) succeeded: code $code_deployer, instantiate permission $(q wasm code-info "$code_deployer" | jq -c .instantiate_permission)"

for code in "$code_before" "$code_deployer"; do
	tx="$(instantiate bob "$code")"
	[ "$(echo "$tx" | jq -r .code)" = "0" ] || die "bob could not instantiate code $code: $(echo "$tx" | jq -r .raw_log)"
	log "bob instantiated code $code: $(event_attr "$tx" instantiate _contract_address)"
done

# ------------------------------------------------------------------ rollback
step "5/5 rollback proposal ($(basename "$ROLLBACK_PROPOSAL"), regular voting period $VOTING_PERIOD)"
secs="$(pass_proposal "$ROLLBACK_PROPOSAL" false)"
log "rollback proposal passed after ${secs}s"
log "wasm params: $(q wasm params | jq -c '.params // .')"
tx="$(store_code bob)"
[ "$(echo "$tx" | jq -r .code)" = "0" ] || die "upload by bob after rollback failed: $(echo "$tx" | jq -r .raw_log)"
log "upload by bob after rollback succeeded: code $(event_attr "$tx" store_code code_id)"

echo
echo "========================================================================"
echo " WASM UPLOAD RESTRICTION TEST PASSED ($("$BINARY" version --home "$HOME_DIR"))"
echo " node keeps running; stop with: scripts/localnet.sh stop"
echo "========================================================================"
