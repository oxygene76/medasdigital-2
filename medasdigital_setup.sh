#!/usr/bin/env bash
# =============================================================================
# medasdigital_setup.sh  –  set up and maintain a MedasDigital node
# Chain: medasdigital-2                                    Script version: 2.2
#
#   New node:       sudo ./medasdigital_setup.sh install
#                   sudo ./medasdigital_setup.sh init <moniker> [--genesis-sync]
#                   sudo ./medasdigital_setup.sh service
#                   sudo systemctl start medasdigitald
#
#   Existing node:  sudo ./medasdigital_setup.sh migrate     (switch to cosmovisor)
#
#   Upgrades:       sudo ./medasdigital_setup.sh prepare-upgrade <name>
#   Status:         ./medasdigital_setup.sh status
#
# Every download is pinned and verified with SHA-256. The script never creates,
# imports, copies or modifies validator keys (priv_validator_key.json) or wallets.
# Settings can be overridden with environment variables (see CONFIGURATION),
# e.g.  NODE_HOME=/data/.medasdigital sudo -E ./medasdigital_setup.sh status
# =============================================================================

set -Eeuo pipefail
umask 022

# ------------------------------------------------------------- CONFIGURATION --
CHAIN_ID="${CHAIN_ID:-medasdigital-2}"
DAEMON_NAME="medasdigitald"
NODE_USER="${NODE_USER:-root}"
NODE_HOME="${NODE_HOME:-$(getent passwd "$NODE_USER" | cut -d: -f6)/.medasdigital}"
CV_DIR="${NODE_HOME}/cosmovisor"
BIN_LINK="/usr/local/bin/${DAEMON_NAME}"
COSMOVISOR_BIN="/usr/local/bin/cosmovisor"
UNIT_FILE="/etc/systemd/system/${DAEMON_NAME}.service"
LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:26657}"
MIN_GAS_PRICE="${MIN_GAS_PRICE:-0.025umedas}"

# Public peers of the MedasDigital nodes (Neptun, Uranus, Saturn). Further peers
# are found automatically through peer exchange.
PEERS="${PEERS:-51ca3b0a3663af88566b32ecfd77948e55000bcc@88.205.101.195:26656,90be2e9f0a279372d2931e38f15025db9a847dbd@88.205.101.196:26656,044b317a7218210da4b0864d4b2ca0e1bf5ea078@88.205.101.197:26656}"
STATE_SYNC_RPC="${STATE_SYNC_RPC:-https://rpc.medas-digital.io:26657}"
# Optional second, independent RPC used as light-client witness (defaults to the first)
STATE_SYNC_RPC2="${STATE_SYNC_RPC2:-$STATE_SYNC_RPC}"

# Pinned artifacts. Never change a hash without verifying the new file yourself.
SRC_COMMIT="050907c763e1dc806f8db3377c6ab3e5dfbf1ecc"
RAW_BASE="https://raw.githubusercontent.com/oxygene76/medasdigital-2/${SRC_COMMIT}"
GENESIS_URL="${GENESIS_URL:-${RAW_BASE}/genesis/mainnet/config/genesis.json}"
GENESIS_SHA256="${GENESIS_SHA256:-e4c22a18aa3a9577fa0565785bc6dfe1648a43f47c0e6bbcb5f236a6f635f9b0}"

# The binary the chain started with (v1.0.1, dynamically linked to libwasmvm 2.1.2)
GENESIS_VERSION="v1.0.1"
GENESIS_BIN_URL="${GENESIS_BIN_URL:-https://github.com/oxygene76/medasdigital-2/releases/download/v1.0.1/medasdigitald}"
GENESIS_BIN_SHA256="${GENESIS_BIN_SHA256:-676a9d2f4f0648994a7da8b30ab4fbbd69018bd82c23f1c077e2b01044871a68}"
LIBWASMVM_PATH="/usr/lib/libwasmvm.x86_64.so"
LIBWASMVM_URL="https://github.com/CosmWasm/wasmvm/releases/download/v2.1.2/libwasmvm.x86_64.so"
LIBWASMVM_SHA256="015bdae5e70304f1e487981f90e3956754718fe7bdac4446aab0838fcb8b33e0"

COSMOVISOR_URL="https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.7.1/cosmovisor-v1.7.1-linux-amd64.tar.gz"
COSMOVISOR_SHA256="014d9a9f8b5b3322642b450943e8fd5323a9b805f26aec9b24d52cc7c4c3bcff"
COSMOVISOR_BIN_SHA256="be8424b018d3b934ccab875efcf23f82e92369df3681d092f13a5a7d4754fe1a"

# Chain upgrades, oldest first:  "<upgrade name>|<app version>|<url>|<sha256>"
# The upgrade name must match the name in the governance upgrade proposal.
UPGRADES=(
  "v2|v2.0.0|https://github.com/oxygene76/medasdigital-2/releases/download/v2.0.0/medasdigitald|1158578518b024dc4b44ea6ea77584a6186463b3fbf6451e3713932fa50e26d2"
)

# ------------------------------------------------------------------ HELPERS --
TMP_DIR=""
cleanup() { if [[ -n "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi; }
trap cleanup EXIT

if [[ -t 1 ]]; then C_OK=$'\e[1;32m'; C_WARN=$'\e[1;33m'; C_ERR=$'\e[1;31m'; C_END=$'\e[0m'
else C_OK=""; C_WARN=""; C_ERR=""; C_END=""; fi
info() { printf '%s==>%s %s\n' "$C_OK" "$C_END" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$C_WARN" "$C_END" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_ERR" "$C_END" "$*" >&2; exit 1; }

confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  [[ -t 0 ]] || die "Confirmation needed but no terminal available (set ASSUME_YES=1 to skip)."
  local answer
  read -r -p "$1 [yes/no]: " answer
  [[ "$answer" == "yes" ]]
}

need_root() { [[ $EUID -eq 0 ]] || die "Please run as root (sudo)."; }

need_cmds() {
  local c missing=()
  for c in "$@"; do command -v "$c" >/dev/null || missing+=("$c"); done
  ((${#missing[@]} == 0)) && return 0
  if [[ $EUID -eq 0 ]] && command -v apt-get >/dev/null; then
    info "Installing missing tools: ${missing[*]}"
    apt-get update -qq || warn "apt-get update reported errors; trying to install anyway."
    apt-get install -y -qq "${missing[@]}" >/dev/null || die "Could not install: ${missing[*]}"
  else
    die "Missing tools: ${missing[*]}"
  fi
}

need_systemd() { command -v systemctl >/dev/null || die "systemd (systemctl) is required."; }

check_user() { id "$NODE_USER" >/dev/null 2>&1 || die "User '$NODE_USER' does not exist."; }

as_node_user() {
  if [[ "$NODE_USER" == "root" || "$(id -un)" == "$NODE_USER" ]]; then "$@"
  else runuser -u "$NODE_USER" -- "$@"; fi
}

fix_owner() { if [[ "$NODE_USER" != "root" ]]; then chown -R "$NODE_USER": "$@"; fi; }

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

# fetch_verified <url> <sha256> <destination> [mode]
# Downloads, verifies and installs a file. Never overwrites a different existing file.
fetch_verified() {
  local url=$1 sha=$2 dest=$3 mode=${4:-0644} tmp
  if [[ -f "$dest" ]]; then
    [[ "$(sha_of "$dest")" == "$sha" ]] && { info "Present and verified: $dest"; return 0; }
    die "$dest exists with a different checksum. Refusing to overwrite it."
  fi
  tmp="$TMP_DIR/download.$$"
  info "Downloading $(basename "$dest") ..."
  curl -fsSL --retry 3 -o "$tmp" "$url" || die "Download failed: $url"
  [[ "$(sha_of "$tmp")" == "$sha" ]] \
    || die "Checksum mismatch for $url (expected $sha, got $(sha_of "$tmp"))."
  install -D -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  info "Verified: $dest"
}

has_old_style_service() { [[ -f "$UNIT_FILE" ]] && ! grep -q "cosmovisor run" "$UNIT_FILE"; }

# Matches only processes whose command line starts with the node binary ("... /medasdigitald start ...")
NODE_PROC_RE="^([^ ]*/)?${DAEMON_NAME} start( |$)"
node_running() { pgrep -f "$NODE_PROC_RE" >/dev/null; }

wait_for_node_stop() {
  local t=$1
  while node_running; do
    ((t-- > 0)) || return 1
    sleep 1
  done
}

rpc() { curl -fsS -m 5 "$1"; }

local_height() { rpc "$LOCAL_RPC/status" | jq -r '.result.sync_info.latest_block_height'; }

# Chain ID of the node in NODE_HOME (falls back to CHAIN_ID)
node_chain_id() {
  local id=""
  if [[ -f "$NODE_HOME/config/genesis.json" ]]; then
    id=$(jq -r '.chain_id // empty' "$NODE_HOME/config/genesis.json" 2>/dev/null || true)
  fi
  echo "${id:-$CHAIN_ID}"
}

block_epoch() {  # block_epoch <height> -> unix time with fractions
  local t
  t=$(rpc "$LOCAL_RPC/block?height=$1" | jq -r '.result.block.header.time') || return 1
  date -d "$t" +%s.%N
}

# For an active validator: print voting power and how long it may be offline
# before it gets jailed. Prints nothing for non-validators.
validator_report() {
  local bin=$1 vp total p window minsigned h h0 e1 e0 budget
  vp=$(rpc "$LOCAL_RPC/status" 2>/dev/null | jq -r '.result.validator_info.voting_power' 2>/dev/null) || return 0
  [[ "$vp" =~ ^[0-9]+$ ]] && ((vp > 0)) || return 0
  total=$(rpc "$LOCAL_RPC/validators?per_page=100" 2>/dev/null \
    | jq '[.result.validators[].voting_power | tonumber] | add' 2>/dev/null) || total=0
  echo
  warn "This node is an ACTIVE VALIDATOR (voting power $vp of $total)."
  p=$("$bin" query slashing params --node "$LOCAL_RPC" -o json 2>/dev/null) || return 0
  window=$(jq -r '.params.signed_blocks_window // .signed_blocks_window // empty' <<<"$p")
  minsigned=$(jq -r '.params.min_signed_per_window // .min_signed_per_window // empty' <<<"$p")
  [[ -n "$window" && -n "$minsigned" ]] || return 0
  budget=$(awk -v w="$window" -v m="$minsigned" 'BEGIN { printf "%d", w * (1 - m) }')
  local msg="about $budget blocks"
  if h=$(local_height 2>/dev/null) && [[ "$h" =~ ^[0-9]+$ ]] && ((h > 100)); then
    h0=$((h - 100))
    if e1=$(block_epoch "$h" 2>/dev/null) && e0=$(block_epoch "$h0" 2>/dev/null); then
      msg="$msg = $(awk -v b="$budget" -v a="$e1" -v z="$e0" \
        'BEGIN { printf "%.1f minutes (block time %.1f s)", b * (a - z) / 100 / 60, (a - z) / 100 }')"
    fi
  fi
  warn "Downtime budget: $msg."
  warn "Blocks already missed in the current window reduce this budget. A node with a large"
  warn "database can need several minutes to start. Switch at a quiet time and watch the output."
}

# Wait until the local node reports a growing block height.
verify_node_progress() {
  local deadline=$((SECONDS + ${1:-300})) h1="" h2
  info "Waiting for the node to process new blocks (up to ${1:-300}s) ..."
  while ((SECONDS < deadline)); do
    if h2=$(local_height 2>/dev/null) && [[ "$h2" =~ ^[0-9]+$ ]]; then
      if [[ -z "$h1" ]]; then h1=$h2
      elif ((h2 > h1)); then info "Node is running: height $h1 -> $h2"; return 0; fi
    fi
    sleep 3
  done
  return 1
}

set_current() {  # set_current genesis|<upgrade name>
  local target="$CV_DIR/genesis"
  [[ "$1" == "genesis" ]] || target="$CV_DIR/upgrades/$1"
  [[ -x "$target/bin/$DAEMON_NAME" ]] || die "No binary in $target/bin"
  ln -sfn "$target" "$CV_DIR/current"
}

link_cli() {  # /usr/local/bin/medasdigitald always points to the active binary
  if [[ -e "$BIN_LINK" && ! -L "$BIN_LINK" ]]; then
    mv "$BIN_LINK" "$BIN_LINK.pre-cosmovisor"
    info "Old binary kept as $BIN_LINK.pre-cosmovisor"
  fi
  ln -sfn "$CV_DIR/current/bin/$DAEMON_NAME" "$BIN_LINK"
}

install_cosmovisor() {
  if [[ -x "$COSMOVISOR_BIN" ]]; then
    if [[ "$(sha_of "$COSMOVISOR_BIN")" == "$COSMOVISOR_BIN_SHA256" ]]; then
      info "cosmovisor v1.7.1 present and verified."
    else
      warn "Keeping the existing $COSMOVISOR_BIN (not the pinned v1.7.1)."
    fi
    return 0
  fi
  fetch_verified "$COSMOVISOR_URL" "$COSMOVISOR_SHA256" "$TMP_DIR/cosmovisor.tar.gz"
  tar -xzf "$TMP_DIR/cosmovisor.tar.gz" -C "$TMP_DIR" cosmovisor
  [[ "$(sha_of "$TMP_DIR/cosmovisor")" == "$COSMOVISOR_BIN_SHA256" ]] \
    || die "Unexpected cosmovisor binary inside the verified archive."
  install -m 0755 "$TMP_DIR/cosmovisor" "$COSMOVISOR_BIN"
  info "Installed cosmovisor v1.7.1 to $COSMOVISOR_BIN"
}

# libwasmvm is only needed by the dynamically linked genesis binary (v1.0.1).
ensure_libwasmvm() {
  if [[ -f "$LIBWASMVM_PATH" ]]; then
    local have; have=$(sha_of "$LIBWASMVM_PATH")
    [[ "$have" == "$LIBWASMVM_SHA256" ]] && { info "libwasmvm 2.1.2 present and verified."; return 0; }
    die "$LIBWASMVM_PATH exists but is not libwasmvm 2.1.2 (sha256 $have). Not replacing it, because a running node may depend on it. Please check manually."
  fi
  fetch_verified "$LIBWASMVM_URL" "$LIBWASMVM_SHA256" "$LIBWASMVM_PATH" 0644
  ldconfig
}

# install_upgrades [name] – pre-place verified upgrade binaries for cosmovisor
install_upgrades() {
  local want="${1:-}" entry name ver url sha dest v found=0
  for entry in ${UPGRADES[@]+"${UPGRADES[@]}"}; do
    IFS='|' read -r name ver url sha <<<"$entry"
    [[ -z "$want" || "$want" == "$name" ]] || continue
    found=1
    dest="$CV_DIR/upgrades/$name/bin/$DAEMON_NAME"
    if [[ -z "$want" && ! -f "$dest" ]] && ! curl -fsIL --retry 2 -o /dev/null "$url"; then
      warn "Upgrade '$name' is not published yet – skipped. Run '$0 prepare-upgrade $name' once it is released."
      continue
    fi
    fetch_verified "$url" "$sha" "$dest" 0755
    v=$("$dest" version 2>/dev/null || true)
    [[ "$v" == "$ver" ]] || die "Upgrade binary '$name' reports version '$v', expected '$ver'."
    if ldd "$dest" 2>/dev/null | grep libwasmvm >/dev/null; then
      warn "Upgrade binary '$name' is dynamically linked to libwasmvm. Do NOT replace $LIBWASMVM_PATH while the old version runs."
    fi
    info "Upgrade '$name' ($ver) is prepared for cosmovisor."
  done
  if [[ -n "$want" && $found -eq 0 ]]; then
    die "Unknown upgrade '$want'. Update this script to a version that knows it."
  fi
}

# Which binary matches the network's current version (for state sync)?
statesync_binary() {
  local v entry name ver
  v=$(rpc "$STATE_SYNC_RPC/abci_info" | jq -r '.result.response.version') \
    || die "State sync RPC $STATE_SYNC_RPC is not reachable. Fix STATE_SYNC_RPC or use --genesis-sync."
  if [[ "$v" == "$GENESIS_VERSION" ]]; then echo genesis; return; fi
  for entry in ${UPGRADES[@]+"${UPGRADES[@]}"}; do
    IFS='|' read -r name ver _ _ <<<"$entry"
    if [[ "$ver" == "$v" ]]; then echo "$name"; return; fi
  done
  die "The network runs version '$v', which this script does not know. Please use a newer script."
}

render_unit() {
  cat <<EOF
[Unit]
Description=MedasDigital node ($(node_chain_id)) via cosmovisor
Wants=network-online.target
After=network-online.target

[Service]
User=${NODE_USER}
ExecStart=${COSMOVISOR_BIN} run start --home ${NODE_HOME}
Restart=always
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${NODE_HOME}"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
# Upgrade binaries are pre-placed and verified by this script, never downloaded by cosmovisor.
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
# Cosmovisor would otherwise copy the whole data directory (hundreds of GB) before
# an upgrade, delaying the node for a long time. Make your own backup/VM snapshot.
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF
}

print_rollback() {
  echo
  echo "Rollback (only valid as long as no chain upgrade has happened):"
  echo "  systemctl stop ${DAEMON_NAME}"
  echo "  cp ${UNIT_FILE}.pre-cosmovisor ${UNIT_FILE}"
  if [[ -e "${BIN_LINK}.pre-cosmovisor" ]]; then
    echo "  rm ${BIN_LINK} && mv ${BIN_LINK}.pre-cosmovisor ${BIN_LINK}"
  fi
  echo "  systemctl daemon-reload && systemctl start ${DAEMON_NAME}"
}

# ----------------------------------------------------------------- COMMANDS --
cmd_install() {
  need_root; check_user; need_cmds curl jq tar
  [[ "$(uname -m)" == "x86_64" ]] || die "Only x86_64 (amd64) is supported."
  has_old_style_service && die "An existing node service was found ($UNIT_FILE). Use '$0 migrate' instead."
  if [[ -L "$BIN_LINK" && "$(readlink "$BIN_LINK")" != "$CV_DIR/current/bin/$DAEMON_NAME" ]]; then
    die "$BIN_LINK already points to another installation ($(readlink "$BIN_LINK")). Only one node per machine is supported."
  fi

  install_cosmovisor
  ensure_libwasmvm
  fetch_verified "$GENESIS_BIN_URL" "$GENESIS_BIN_SHA256" "$CV_DIR/genesis/bin/$DAEMON_NAME" 0755
  install_upgrades
  [[ -L "$CV_DIR/current" ]] || set_current genesis
  link_cli
  fix_owner "$CV_DIR"
  info "Installation complete. Next: $0 init <moniker>"
}

cmd_init() {
  local moniker="${1:-}" mode="statesync" run="genesis" bin
  [[ -n "$moniker" ]] || die "Usage: $0 init <moniker> [--genesis-sync]"
  [[ "${2:-}" == "--genesis-sync" ]] && mode="genesis"
  need_root; check_user; need_cmds curl jq
  [[ -e "$NODE_HOME/config" ]] && die "$NODE_HOME is already initialized. Refusing to touch it (this protects existing keys)."
  [[ -x "$CV_DIR/genesis/bin/$DAEMON_NAME" ]] || die "Run '$0 install' first."

  # Collect everything from the network first, so a failure leaves nothing half-done.
  local latest="" trust_height="" trust_hash=""
  if [[ "$mode" == "statesync" ]]; then
    run=$(statesync_binary)
    latest=$(rpc "$STATE_SYNC_RPC/block" | jq -r '.result.block.header.height') || true
    [[ "$latest" =~ ^[0-9]+$ ]] || die "Could not read the latest height from $STATE_SYNC_RPC."
    trust_height=$((latest > 2000 ? latest - 2000 : 1))
    trust_hash=$(rpc "$STATE_SYNC_RPC/block?height=$trust_height" | jq -r '.result.block_id.hash') || true
    [[ "$trust_hash" =~ ^[0-9A-F]{64}$ ]] || die "Could not read the block hash at height $trust_height."
    if [[ "$STATE_SYNC_RPC2" != "$STATE_SYNC_RPC" ]]; then
      local hash2
      hash2=$(rpc "$STATE_SYNC_RPC2/block?height=$trust_height" | jq -r '.result.block_id.hash') || true
      [[ "$hash2" == "$trust_hash" ]] \
        || die "The two state sync RPCs disagree about block $trust_height (or the second one is unreachable)."
      info "Both state sync RPCs agree on block $trust_height."
    fi
  fi
  set_current "$run"
  bin="$CV_DIR/current/bin/$DAEMON_NAME"

  info "Initializing node '$moniker' in $NODE_HOME ($(basename "$(readlink -f "$CV_DIR/current")") binary) ..."
  fix_owner "$NODE_HOME"
  as_node_user "$bin" init "$moniker" --chain-id "$CHAIN_ID" --home "$NODE_HOME" >"$TMP_DIR/init.log" 2>&1 \
    || { cat "$TMP_DIR/init.log" >&2; die "init failed."; }

  rm -f "$NODE_HOME/config/genesis.json"
  fetch_verified "$GENESIS_URL" "$GENESIS_SHA256" "$NODE_HOME/config/genesis.json"

  local set=(as_node_user "$bin" config set --home "$NODE_HOME")
  "${set[@]}" client chain-id "$CHAIN_ID"
  "${set[@]}" client keyring-backend file
  "${set[@]}" app minimum-gas-prices "$MIN_GAS_PRICE"
  "${set[@]}" app pruning custom
  "${set[@]}" app pruning-keep-recent 100
  "${set[@]}" app pruning-interval 10
  "${set[@]}" app state-sync.snapshot-interval 1000
  "${set[@]}" app state-sync.snapshot-keep-recent 2
  "${set[@]}" -s config p2p.persistent_peers "$PEERS"

  if [[ "$mode" == "statesync" ]]; then
    "${set[@]}" -s config statesync.enable true
    "${set[@]}" -s config statesync.rpc_servers "$STATE_SYNC_RPC,$STATE_SYNC_RPC2"
    "${set[@]}" -s config statesync.trust_height "$trust_height"
    "${set[@]}" -s config statesync.trust_hash "$trust_hash"
    "${set[@]}" -s config statesync.trust_period "168h0m0s"
    info "State sync configured (trust height $trust_height)."
  else
    warn "Genesis sync replays every block since November 2024. This takes days and needs 250+ GB."
  fi

  fix_owner "$NODE_HOME"
  info "Node initialized. Next: $0 service"
}

cmd_service() {
  need_root; need_systemd
  has_old_style_service && die "$UNIT_FILE exists without cosmovisor. For an existing node use: $0 migrate"
  [[ -f "$NODE_HOME/config/genesis.json" ]] || die "No initialized node in $NODE_HOME."
  [[ -x "$COSMOVISOR_BIN" && -L "$CV_DIR/current" ]] || die "cosmovisor is not set up – run '$0 install' first."
  if [[ -f "$UNIT_FILE" ]] && ! grep -qF "DAEMON_HOME=${NODE_HOME}\"" "$UNIT_FILE"; then
    die "$UNIT_FILE belongs to another node ($(grep -oP 'DAEMON_HOME=\K[^"]+' "$UNIT_FILE" || echo "unknown home")). Only one node per machine is supported."
  fi
  render_unit >"$UNIT_FILE"
  systemctl daemon-reload
  systemctl enable "$DAEMON_NAME" >/dev/null 2>&1
  info "Service installed and enabled. Start: systemctl start $DAEMON_NAME   Logs: journalctl -fu $DAEMON_NAME"
}

cmd_migrate() {
  need_root; check_user; need_systemd; need_cmds curl jq tar
  [[ -f "$UNIT_FILE" ]] || die "No $UNIT_FILE found – nothing to migrate."
  grep -q "cosmovisor run" "$UNIT_FILE" && { info "The node already runs via cosmovisor."; return 0; }
  [[ -f "$NODE_HOME/config/genesis.json" ]] || die "No node found in $NODE_HOME (set NODE_HOME=...)."

  # --- check the existing setup ---------------------------------------------
  local old_bin real_bin ver sha unit_home unit_user
  old_bin=$(grep -oP '^ExecStart=\s*\K\S+' "$UNIT_FILE")
  real_bin=$(readlink -f "$old_bin")
  [[ -x "$real_bin" ]] || die "Cannot find the node binary from ExecStart ($old_bin)."
  unit_home=$(grep -oP -- '--home[= ]\K\S+' "$UNIT_FILE" || true)
  if [[ -n "$unit_home" && "$(readlink -f "$unit_home")" != "$(readlink -f "$NODE_HOME")" ]]; then
    die "The service uses --home $unit_home. Re-run with NODE_HOME=$unit_home"
  fi
  unit_user=$(grep -oP '^User=\K\S+' "$UNIT_FILE" || echo root)
  [[ "$unit_user" == "$NODE_USER" ]] || die "The service runs as '$unit_user'. Re-run with NODE_USER=$unit_user"
  local extra
  extra=$(grep -oP '^ExecStart=\s*\S+\s*\K.*' "$UNIT_FILE" \
    | sed -E 's/(^| )start( |$)/ /; s/--home[= ][^ ]+//' | xargs || true)
  [[ -z "$extra" ]] \
    || die "The service starts the node with extra options ($extra). They would be lost when switching. Move them into config.toml/app.toml first."
  if grep -qE '^(Environment|EnvironmentFile)=' "$UNIT_FILE"; then
    die "The service sets environment variables (Environment=/EnvironmentFile=). They would be lost when switching. Move them into the node configuration first."
  fi
  ver=$("$real_bin" version 2>/dev/null) || die "The binary $real_bin does not run."
  sha=$(sha_of "$real_bin")
  if [[ "$sha" != "$GENESIS_BIN_SHA256" ]]; then
    warn "Your binary (version '$ver', sha256 $sha) is not the official $GENESIS_VERSION build (self-built?)."
    warn "It is kept exactly as it is, because your node currently runs fine with it."
    confirm "Continue with this binary?" || die "Aborted."
  fi
  if [[ "$(pgrep -fc "$NODE_PROC_RE" || true)" -gt 1 ]]; then
    die "More than one '$DAEMON_NAME start' process is running. Resolve this first."
  fi
  if [[ -e "$CV_DIR/genesis/bin/$DAEMON_NAME" ]] && ! cmp -s "$real_bin" "$CV_DIR/genesis/bin/$DAEMON_NAME"; then
    die "$CV_DIR/genesis/bin/$DAEMON_NAME already exists and differs from the running binary."
  fi

  # --- prepare while the node keeps running ----------------------------------
  install_cosmovisor
  install -D -m 0755 "$real_bin" "$CV_DIR/genesis/bin/$DAEMON_NAME"
  set_current genesis
  install_upgrades
  fix_owner "$CV_DIR"
  env DAEMON_NAME="$DAEMON_NAME" DAEMON_HOME="$NODE_HOME" "$COSMOVISOR_BIN" version >/dev/null 2>&1 \
    || die "cosmovisor cannot use the prepared layout in $CV_DIR."
  render_unit >"$TMP_DIR/new.service"
  echo
  echo "--- Changes to $UNIT_FILE:"
  diff -u "$UNIT_FILE" "$TMP_DIR/new.service" || true
  echo
  info "Keys and data stay untouched. The node is stopped once and restarted via cosmovisor."
  validator_report "$real_bin"
  confirm "Switch now? The node is offline until it has restarted." \
    || die "Aborted. Only $CV_DIR and $COSMOVISOR_BIN were added; the node keeps running unchanged."

  # --- switch ---------------------------------------------------------------
  systemctl stop "$DAEMON_NAME"
  wait_for_node_stop 90 \
    || die "The node process is still running after stop. Nothing was started. Please check manually."
  cp -a "$UNIT_FILE" "$UNIT_FILE.pre-cosmovisor"
  install -m 0644 "$TMP_DIR/new.service" "$UNIT_FILE"
  link_cli
  systemctl daemon-reload
  node_running && die "A node process appeared unexpectedly. Not starting a second one."
  systemctl start "$DAEMON_NAME"

  if verify_node_progress 300; then
    info "Migration complete. The node now runs via cosmovisor."
    print_rollback
  else
    warn "The node did not show new blocks within 5 minutes. Check: journalctl -u $DAEMON_NAME -n 100"
    print_rollback
    exit 1
  fi
}

cmd_prepare_upgrade() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "Usage: $0 prepare-upgrade <name>"
  need_root; check_user; need_cmds curl
  [[ -d "$CV_DIR/genesis" ]] || die "No cosmovisor setup in $CV_DIR. Run install or migrate first."
  install_upgrades "$name"
  fix_owner "$CV_DIR"
  info "Cosmovisor will switch automatically at the upgrade height. Keep $LIBWASMVM_PATH unchanged."
}

cmd_status() {
  need_cmds curl jq
  local active s plan pname pheight
  echo "Node home        : $NODE_HOME"
  if has_old_style_service; then
    local b; b=$(grep -oP '^ExecStart=\s*\K\S+' "$UNIT_FILE")
    echo "Active binary    : $b ($("$b" version 2>/dev/null || echo "not runnable"))"
    echo "Cosmovisor       : NOT used by the service (see '$0 migrate')"
  elif [[ -L "$CV_DIR/current" ]]; then
    active=$(basename "$(readlink -f "$CV_DIR/current")")
    echo "Active binary    : $active ($("$CV_DIR/current/bin/$DAEMON_NAME" version 2>/dev/null || echo "not runnable"))"
    for d in "$CV_DIR"/upgrades/*/; do
      [[ -d "$d" ]] && echo "Prepared upgrade : $(basename "$d") ($("$d/bin/$DAEMON_NAME" version 2>/dev/null || echo "not runnable"))"
    done
  else
    echo "Active binary    : no cosmovisor setup (use '$0 migrate')"
  fi
  if command -v systemctl >/dev/null; then
    echo "Service          : $(systemctl is-active "$DAEMON_NAME" 2>/dev/null || true)"
  fi
  if ! s=$(rpc "$LOCAL_RPC/status" 2>/dev/null); then
    echo "Node RPC         : not reachable at $LOCAL_RPC"
    return 0
  fi
  echo "Chain            : $(jq -r .result.node_info.network <<<"$s")"
  echo "Block height     : $(jq -r .result.sync_info.latest_block_height <<<"$s") ($(jq -r .result.sync_info.latest_block_time <<<"$s"))"
  echo "Catching up      : $(jq -r .result.sync_info.catching_up <<<"$s")"
  echo "Voting power     : $(jq -r .result.validator_info.voting_power <<<"$s")"
  echo "Peers            : $(rpc "$LOCAL_RPC/net_info" | jq -r .result.n_peers)"
  if plan=$("$BIN_LINK" query upgrade plan --node "$LOCAL_RPC" -o json 2>/dev/null) && [[ -n "$plan" ]]; then
    pname=$(jq -r '.name // .plan.name // empty' <<<"$plan")
    pheight=$(jq -r '.height // .plan.height // empty' <<<"$plan")
    if [[ -n "$pname" ]]; then
      echo "Scheduled upgrade: $pname at height $pheight"
      [[ -x "$CV_DIR/upgrades/$pname/bin/$DAEMON_NAME" ]] \
        || warn "Upgrade '$pname' is scheduled but NOT prepared. Run: sudo $0 prepare-upgrade $pname"
      return 0
    fi
  fi
  echo "Scheduled upgrade: none"
}

usage() {
  cat <<EOF
MedasDigital node setup (chain $CHAIN_ID)

New node:
  sudo $0 install                       Install cosmovisor and verified binaries
  sudo $0 init <moniker> [--genesis-sync]
                                        Initialize the node (state sync by default)
  sudo $0 service                       Create the systemd service
  sudo systemctl start $DAEMON_NAME

Existing node:
  sudo $0 migrate                       Switch the running node to cosmovisor

Maintenance:
  sudo $0 prepare-upgrade <name>        Pre-place a verified upgrade binary
  $0 status                             Show installation and node status

Wallets and validators are managed with the binary itself, e.g.
  $DAEMON_NAME keys add <name>
  $DAEMON_NAME tx staking create-validator --help
Create a validator only after the node is fully synced ("Catching up: false").
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true
  TMP_DIR=$(mktemp -d)
  case "$cmd" in
    install)         cmd_install "$@" ;;
    init)            cmd_init "$@" ;;
    service)         cmd_service "$@" ;;
    migrate)         cmd_migrate "$@" ;;
    prepare-upgrade) cmd_prepare_upgrade "$@" ;;
    status)          cmd_status "$@" ;;
    help|-h|--help)  usage ;;
    *)               usage; exit 1 ;;
  esac
}

main "$@"
