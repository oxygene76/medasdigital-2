#!/usr/bin/env bash
#
# Local single-node testnet for medasdigitald.
#
#   scripts/localnet.sh [up]   wipe ./.localnet, init a fresh chain, start the
#                              node in the background, wait for blocks and run
#                              a bank-send smoke test (default)
#   scripts/localnet.sh init   wipe ./.localnet and init a fresh chain (no start)
#   scripts/localnet.sh start  start the node on the existing ./.localnet
#   scripts/localnet.sh stop   stop the background node
#   scripts/localnet.sh smoke  run the bank-send smoke test against a running node
#   scripts/localnet.sh status print height and account balances
#
# Everything lives under ./.localnet (home, test keyring, log, pid). Nothing
# outside that directory is touched and the node only listens on 127.0.0.1.
# Ports are offset by +10000 from the defaults so a real node on the same
# machine is not disturbed; override them via the environment if needed.
#
# The binary defaults to ./bin/medasdigitald; set BINARY to use another one
# (scripts/upgrade-test.sh switches binaries this way). The script can also
# be sourced to reuse its functions.
#
# The keyring backend is "test" (unencrypted). Never use these keys anywhere
# else.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/bin/medasdigitald}"
LOCALNET_DIR="$REPO_ROOT/.localnet"
HOME_DIR="$LOCALNET_DIR/home"
LOG_FILE="$LOCALNET_DIR/node.log"
PID_FILE="$LOCALNET_DIR/node.pid"

CHAIN_ID="medasdigital-local"
DENOM="umedas"
KEYRING="test"
MIN_GAS_PRICE="0.025$DENOM"
FEES="5000$DENOM"
VOTING_PERIOD="60s"
EXPEDITED_VOTING_PERIOD="30s"

P2P_PORT="${P2P_PORT:-36656}"
RPC_PORT="${RPC_PORT:-36657}"
ABCI_PORT="${ABCI_PORT:-36658}"
GRPC_PORT="${GRPC_PORT:-39090}"
API_PORT="${API_PORT:-11317}"
NODE="tcp://127.0.0.1:$RPC_PORT"

VALIDATOR_KEY="validator"
TEST_KEYS=(alice bob)
VALIDATOR_BALANCE="1000000000000$DENOM" # 1,000,000 MEDAS
VALIDATOR_STAKE="100000000000$DENOM"    #   100,000 MEDAS
TEST_BALANCE="1000000000$DENOM"         #     1,000 MEDAS each
SEND_AMOUNT="1234567"                   # umedas, alice -> bob

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

bin() { "$BINARY" --home "$HOME_DIR" "$@"; }

require_tools() {
	[ -x "$BINARY" ] || die "binary not found at $BINARY (run 'make build' first)"
	for t in jq curl; do
		command -v "$t" >/dev/null || die "'$t' is required"
	done
}

# Only ever delete the localnet directory inside this repo.
wipe_localnet() {
	case "$LOCALNET_DIR" in
	"$REPO_ROOT"/.localnet) rm -rf "$LOCALNET_DIR" ;;
	*) die "refusing to delete unexpected path $LOCALNET_DIR" ;;
	esac
}

node_pid() {
	[ -f "$PID_FILE" ] || return 1
	local pid
	pid="$(cat "$PID_FILE")"
	# Make sure the pid still belongs to our node before we act on it.
	if [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- "$HOME_DIR"; then
		echo "$pid"
		return 0
	fi
	return 1
}

stop_node() {
	local pid
	if pid="$(node_pid)"; then
		log "stopping node (pid $pid)"
		kill "$pid"
		for _ in $(seq 1 30); do
			kill -0 "$pid" 2>/dev/null || break
			sleep 0.5
		done
		kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
	fi
	rm -f "$PID_FILE"
}

height() {
	curl -sf "http://127.0.0.1:$RPC_PORT/status" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo 0
}

balance() {
	bin query bank balance "$1" "$DENOM" --node "$NODE" --output json | jq -r '.balance.amount'
}

addr() {
	bin keys show "$1" -a --keyring-backend "$KEYRING"
}

init_chain() {
	log "initialising $CHAIN_ID in $HOME_DIR"
	mkdir -p "$LOCALNET_DIR/keys"
	bin init localnet --chain-id "$CHAIN_ID" --default-denom "$DENOM" >/dev/null 2>&1

	for key in "$VALIDATOR_KEY" "${TEST_KEYS[@]}"; do
		bin keys add "$key" --keyring-backend "$KEYRING" --output json >"$LOCALNET_DIR/keys/$key.json" 2>&1
	done

	bin genesis add-genesis-account "$(addr "$VALIDATOR_KEY")" "$VALIDATOR_BALANCE" --keyring-backend "$KEYRING"
	for key in "${TEST_KEYS[@]}"; do
		bin genesis add-genesis-account "$(addr "$key")" "$TEST_BALANCE" --keyring-backend "$KEYRING"
	done

	# Short governance periods for upgrade tests.
	local genesis="$HOME_DIR/config/genesis.json"
	jq --arg vp "$VOTING_PERIOD" --arg evp "$EXPEDITED_VOTING_PERIOD" '
		.app_state.gov.params.voting_period = $vp
		| .app_state.gov.params.max_deposit_period = $vp
		| .app_state.gov.params.expedited_voting_period = $evp
	' "$genesis" >"$genesis.tmp" && mv "$genesis.tmp" "$genesis"

	bin genesis gentx "$VALIDATOR_KEY" "$VALIDATOR_STAKE" \
		--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" >/dev/null 2>&1
	bin genesis collect-gentxs >/dev/null 2>&1
	bin genesis validate >/dev/null

	if grep -q '"stake"' "$genesis"; then
		die "genesis still contains the default denom 'stake'"
	fi

	local config="$HOME_DIR/config/config.toml"
	local app="$HOME_DIR/config/app.toml"
	sed -i \
		-e "s|^laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://127.0.0.1:$P2P_PORT\"|" \
		-e "s|^laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:$RPC_PORT\"|" \
		-e "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:$ABCI_PORT\"|" \
		-e "s|^pprof_laddr = .*|pprof_laddr = \"\"|" \
		-e "s|^timeout_commit = .*|timeout_commit = \"1s\"|" \
		-e "s|^addr_book_strict = .*|addr_book_strict = false|" \
		"$config"
	sed -i \
		-e "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICE\"|" \
		-e "s|^address = \"localhost:9090\"|address = \"127.0.0.1:$GRPC_PORT\"|" \
		-e "s|^address = \"tcp://localhost:1317\"|address = \"tcp://127.0.0.1:$API_PORT\"|" \
		"$app"
	# Enable the REST API ([api] section only).
	sed -i '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' "$app"

	grep -q "127.0.0.1:$RPC_PORT" "$config" || die "failed to set RPC port in config.toml"
	grep -q "127.0.0.1:$GRPC_PORT" "$app" || die "failed to set gRPC port in app.toml"
}

start_node() {
	log "starting node (log: $LOG_FILE)"
	# Append, so the log of a previous binary (e.g. the upgrade halt) is kept.
	echo "===== $(date -u +%FT%TZ) starting $BINARY =====" >>"$LOG_FILE"
	nohup "$BINARY" start --home "$HOME_DIR" >>"$LOG_FILE" 2>&1 &
	echo $! >"$PID_FILE"
}

wait_for_blocks() {
	local target="${1:-3}"
	log "waiting for block height >= $target"
	for _ in $(seq 1 60); do
		node_pid >/dev/null || die "node exited, see $LOG_FILE"
		local h
		h="$(height)"
		if [ "${h:-0}" -ge "$target" ]; then
			log "block height $h"
			return 0
		fi
		sleep 1
	done
	die "no blocks after 60s, see $LOG_FILE"
}

# Wait until the RPC answers, then until $1 (default 2) further blocks are
# committed. Used after restarting an existing chain.
wait_for_new_blocks() {
	local n="${1:-2}" h0=0
	for _ in $(seq 1 60); do
		node_pid >/dev/null || die "node exited, see $LOG_FILE"
		h0="$(height)"
		[ "${h0:-0}" -gt 0 ] && break
		sleep 1
	done
	[ "${h0:-0}" -gt 0 ] || die "RPC not reachable after 60s, see $LOG_FILE"
	wait_for_blocks $((h0 + n))
}

# Takes the JSON output of a broadcast tx, fails if CheckTx rejected it, waits
# until it is included in a block and fails if DeliverTx failed. Prints the
# included tx as JSON.
wait_tx() {
	local res="$1" code hash
	code="$(echo "$res" | jq -r '.code')"
	hash="$(echo "$res" | jq -r '.txhash')"
	[ "$code" = "0" ] || die "tx rejected by CheckTx: $(echo "$res" | jq -r '.raw_log')"

	for _ in $(seq 1 30); do
		if res="$(bin query tx "$hash" --node "$NODE" --output json 2>/dev/null)"; then
			code="$(echo "$res" | jq -r '.code')"
			[ "$code" = "0" ] || die "tx $hash failed: $(echo "$res" | jq -r '.raw_log')"
			log "tx $hash included at height $(echo "$res" | jq -r '.height')" >&2
			echo "$res"
			return 0
		fi
		sleep 1
	done
	die "tx $hash not found after 30s"
}

smoke_test() {
	local from to before after h1 h2
	from="$(addr alice)"
	to="$(addr bob)"

	h1="$(height)"
	sleep 3
	h2="$(height)"
	[ "$h2" -gt "$h1" ] || die "block production stalled at height $h1"
	log "blocks are being produced ($h1 -> $h2)"

	before="$(balance "$to")"
	log "sending $SEND_AMOUNT$DENOM alice -> bob (bob before: $before)"
	local res
	res="$(bin tx bank send "$from" "$to" "$SEND_AMOUNT$DENOM" \
		--chain-id "$CHAIN_ID" --keyring-backend "$KEYRING" --node "$NODE" \
		--fees "$FEES" --yes --output json)"
	wait_tx "$res" >/dev/null

	after="$(balance "$to")"
	[ "$after" -eq $((before + SEND_AMOUNT)) ] || die "bob balance $after, expected $((before + SEND_AMOUNT))"
	log "smoke test passed (bob after: $after)"
}

status() {
	echo "height: $(height)"
	for key in "$VALIDATOR_KEY" "${TEST_KEYS[@]}"; do
		echo "$key $(addr "$key") $(balance "$(addr "$key")")$DENOM"
	done
}

main() {
	local cmd="${1:-up}"
	require_tools
	case "$cmd" in
	up)
		stop_node
		wipe_localnet
		init_chain
		start_node
		wait_for_blocks 3
		smoke_test
		log "node running: RPC $NODE, gRPC 127.0.0.1:$GRPC_PORT, API http://127.0.0.1:$API_PORT"
		log "stop with: scripts/localnet.sh stop"
		;;
	init)
		stop_node
		wipe_localnet
		init_chain
		;;
	start)
		[ -d "$HOME_DIR" ] || die "no localnet at $HOME_DIR (run init or up first)"
		node_pid >/dev/null && die "node already running"
		start_node
		wait_for_new_blocks 2
		;;
	stop) stop_node ;;
	smoke) smoke_test ;;
	status) status ;;
	*) die "unknown command '$cmd' (use: up | init | start | stop | smoke | status)" ;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
