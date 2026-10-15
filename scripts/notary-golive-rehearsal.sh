#!/usr/bin/env bash
# Rehearsal of docs/runbooks/notary-contract-golive.md, sections 3 to 8, on a
# fresh localnet with the mainnet binary (build/release/medasdigitald, v2.0.0).
#
#   scripts/notary-golive-rehearsal.sh
#
# Like mainnet, code upload is first restricted to one address by a gov
# proposal (wasm MsgUpdateParams). Then the runbook's commands run with the same
# variables; only chain ID, node, keyring and the addresses differ:
#   upload address = contract admin: alice, notary admin: bob.
# WASM: the release file of medas-notary-contract (default
# ../medas-notary-contract/artifacts/medas_notary.wasm), checked against
# WASM_SHA256. Wipes ./.localnet. About 2 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD

export BINARY="${BINARY:-$REPO/build/release/medasdigitald}"
export P2P_PORT=${P2P_PORT:-56656} RPC_PORT=${RPC_PORT:-56657} ABCI_PORT=${ABCI_PORT:-56658} GRPC_PORT=${GRPC_PORT:-59090} API_PORT=${API_PORT:-51317}
WASM="${WASM:-$REPO/../medas-notary-contract/artifacts/medas_notary.wasm}"
CONTRACT_FILE="$REPO/docs/notary/contract.json"
WEB_REPO="${WEB_REPO:-$REPO/../medas-notary-web}"

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "== $*" >&2; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$2', expected '$3'"; echo "   ok: $1" >&2; }
wait_tx() { for _ in $(seq 1 30); do $MD q tx "$1" $Q 2>/dev/null && return; sleep 1; done; fail "transaction $1 not found"; }

"$BINARY" version | grep -q '^v2\.0\.0$' || fail "$BINARY is not v2.0.0"
[ -f "$WASM" ] || fail "missing $WASM"

step "localnet with the mainnet binary"
scripts/localnet.sh up >/dev/null
trap 'scripts/localnet.sh stop >/dev/null 2>&1' EXIT
HOME_DIR="$REPO/.localnet/home"
KR="--keyring-backend test"

# ---------------------------------------------------------------- variables as in section 1
export MD="$BINARY --home $HOME_DIR"
export CHAIN_ID=medasdigital-local
export NODE="tcp://127.0.0.1:$RPC_PORT"
export Q="--node $NODE -o json"
export TX="--node $NODE --chain-id $CHAIN_ID $KR"
export DEPLOY=$($MD keys show alice -a $KR)
export DEPLOY_KEY=alice
export NOTARY_ADMIN=$($MD keys show bob -a $KR)
export RELEASE=v0.2.0
export SOURCE_COMMIT=25cd3e2ae5e8c14e3becea90576901a57e895f03
export WASM_SHA256=1487721ae59465653638cdae9e98fb1a2f45239381cca78a2013d49d47a13e76
WORK=$(mktemp -d)
cd "$WORK"
cp "$WASM" medas_notary.wasm

step "upload restriction as on mainnet (gov proposal, wasm MsgUpdateParams)"
GOV=$($MD q auth module-account gov $Q | jq -r .account.value.address)
cat > restrict.json <<JSON
{"messages":[{"@type":"/cosmwasm.wasm.v1.MsgUpdateParams","authority":"$GOV",
 "params":{"code_upload_access":{"permission":"AnyOfAddresses","addresses":["$DEPLOY"]},"instantiate_default_permission":"Everybody"}}],
 "metadata":"","deposit":"$($MD q gov params $Q | jq -r '.params.min_deposit[0].amount + .params.min_deposit[0].denom')",
 "title":"restrict wasm upload","summary":"rehearsal","expedited":false}
JSON
r=$($MD tx gov submit-proposal restrict.json --from validator $TX --gas 400000 --fees 10000umedas -y -o json)
ID=$(wait_tx "$(jq -r .txhash <<<"$r")" | jq -r '[.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value][0]')
r=$($MD tx gov vote "$ID" yes --from validator $TX --gas 200000 --fees 5000umedas -y -o json)
wait_tx "$(jq -r .txhash <<<"$r")" >/dev/null
for _ in $(seq 1 90); do
	st=$($MD q gov proposal "$ID" $Q | jq -r .proposal.status)
	[ "$st" = PROPOSAL_STATUS_PASSED ] && break
	[ "$st" = PROPOSAL_STATUS_REJECTED ] || [ "$st" = PROPOSAL_STATUS_FAILED ] && fail "proposal $st"
	sleep 2
done
expect "proposal" "$st" PROPOSAL_STATUS_PASSED

# ---------------------------------------------------------------- section 3
step "3. checks before"
$MD status --node $NODE | jq -e '.sync_info.catching_up == false' >/dev/null
expect "wasm params" "$($MD q wasm params $Q | jq -c .)" \
	"{\"code_upload_access\":{\"permission\":\"AnyOfAddresses\",\"addresses\":[\"$DEPLOY\"]},\"instantiate_default_permission\":\"Everybody\"}"
expect "code not yet on chain" "$($MD q wasm list-code $Q | jq -c --arg h "${WASM_SHA256^^}" '[.code_infos[] | select(.data_hash == $h)]')" "[]"
$MD q bank balances $DEPLOY $Q | jq -e '[.balances[] | select(.denom=="umedas") | .amount | tonumber][0] >= 200000' >/dev/null
$MD debug addr $NOTARY_ADMIN >/dev/null
$MD tx wasm store medas_notary.wasm --from $NOTARY_ADMIN $TX --dry-run >out.txt 2>&1 && fail "upload by another address was not refused"
grep -q "unauthorized" out.txt || fail "upload by another address: $(tail -1 out.txt)"
echo "   ok: upload by another address refused" >&2

# ---------------------------------------------------------------- section 4
step "4. upload"
expect "sha256 of the file" "$(sha256sum medas_notary.wasm | cut -c1-64)" "$WASM_SHA256"
$MD tx wasm store medas_notary.wasm --from $DEPLOY $TX --instantiate-anyof-addresses $DEPLOY --dry-run 2>&1 | grep -i "gas estimate" >&2
$MD tx wasm store medas_notary.wasm --from $DEPLOY_KEY $TX \
	--instantiate-anyof-addresses $DEPLOY \
	--gas 3500000 --fees 87500umedas -y -o json | tee store.json >/dev/null
expect "store submit code" "$(jq -r .code store.json)" 0
wait_tx "$(jq -r .txhash store.json)" > store-tx.json
expect "store code" "$(jq -r .code store-tx.json)" 0
echo "   gas used: $(jq -r .gas_used store-tx.json)" >&2
export CODE_ID=$(jq -r '[.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value][0]' store-tx.json)
ci=$($MD q wasm code-info $CODE_ID $Q | jq -c 'del(.data)')
expect "checksum" "$(jq -r .checksum <<<"$ci")" "${WASM_SHA256^^}"
expect "creator" "$(jq -r .creator <<<"$ci")" "$DEPLOY"
expect "instantiate permission" "$(jq -c .instantiate_permission <<<"$ci")" "{\"permission\":\"AnyOfAddresses\",\"addresses\":[\"$DEPLOY\"]}"

# ---------------------------------------------------------------- section 5
step "5. instantiate"
cat > instantiate.json <<JSON
{
  "fee": { "denom": "umedas", "amount": "1000000000" },
  "fee_split": { "burn_bps": 10000, "community_pool_bps": 0, "recipients": [] },
  "start_credit": { "denom": "umedas", "amount": "1002000000" },
  "require_registration": true,
  "notary_admins": ["$NOTARY_ADMIN"]
}
JSON
$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label medas-notary --admin $DEPLOY \
	--from $DEPLOY $TX --dry-run 2>&1 | grep -i "gas estimate" >&2
$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label medas-notary --admin $DEPLOY \
	--from $DEPLOY_KEY $TX --gas 300000 --fees 7500umedas -y -o json | tee instantiate-submit.json >/dev/null
expect "instantiate submit code" "$(jq -r .code instantiate-submit.json)" 0
wait_tx "$(jq -r .txhash instantiate-submit.json)" > instantiate-tx.json
expect "instantiate code" "$(jq -r .code instantiate-tx.json)" 0
echo "   gas used: $(jq -r .gas_used instantiate-tx.json)" >&2
export CONTRACT=$(jq -r '[.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value][0]' instantiate-tx.json)
export INSTANTIATE_TX=$(jq -r .txhash instantiate-tx.json)
export H=$(jq -r .height instantiate-tx.json)
echo "   contract $CONTRACT, height $H" >&2

# ---------------------------------------------------------------- section 6
step "6. checks after"
S() { $MD q wasm contract-state smart $CONTRACT "$1" $Q | jq -c .data; }
expect "contract info" "$($MD q wasm contract $CONTRACT $Q | jq -c '.contract_info | {code_id, creator, admin, label}')" \
	"{\"code_id\":\"$CODE_ID\",\"creator\":\"$DEPLOY\",\"admin\":\"$DEPLOY\",\"label\":\"medas-notary\"}"
expect "code hash" "$($MD q wasm code-info $CODE_ID $Q | jq -r .checksum | tr A-F a-f)" "$WASM_SHA256"
expect "config" "$(S '{"config":{}}')" \
	'{"fee":{"denom":"umedas","amount":"1000000000"},"fee_split":{"burn_bps":10000,"community_pool_bps":0,"recipients":[]},"start_credit":{"denom":"umedas","amount":"1002000000"},"require_registration":true,"commits":0,"contract":"medas-notary","version":"0.2.0"}'
expect "notary admins" "$(S '{"notary_admins":{}}' | jq -c '[.notary_admins[] | {address, periods: [.periods[] | [.from_height, .until_height]]}]')" \
	"[{\"address\":\"$NOTARY_ADMIN\",\"periods\":[[$((H + 1)),null]]}]"
expect "notary admin at H" "$(S "{\"notary_admin_at\":{\"address\":\"$NOTARY_ADMIN\",\"height\":$H}}")" false
expect "notary admin at H+1" "$(S "{\"notary_admin_at\":{\"address\":\"$NOTARY_ADMIN\",\"height\":$((H + 1))}}")" true
expect "contract admin is no notary admin" "$(S "{\"notary_admin_at\":{\"address\":\"$DEPLOY\",\"height\":$((H + 1))}}")" false
expect "contract balance" "$($MD q bank balances $CONTRACT $Q | jq -c .balances)" "[]"
$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label x --no-admin \
	--from $NOTARY_ADMIN $TX --dry-run >out.txt 2>&1 && fail "instantiation by another address was not refused"
grep -q "unauthorized" out.txt || fail "instantiation by another address: $(tail -1 out.txt)"
echo "   ok: instantiation by another address refused" >&2

# ---------------------------------------------------------------- section 7 (on a copy)
step "7. entry in contract.json (copy)"
cp "$CONTRACT_FILE" contract.json
jq --arg addr "$CONTRACT" --arg tx "$INSTANTIATE_TX" --arg admin "$DEPLOY" \
   --argjson code "$CODE_ID" --arg sha "$WASM_SHA256" --arg tag "$RELEASE" --arg commit "$SOURCE_COMMIT" \
   --argjson h "$H" \
   '.networks["medasdigital-2"] = {address: $addr, instantiate_tx: $tx, contract_admin: $admin,
     codes: [{code_id: $code, code_sha256: $sha,
              source: {repository: "https://github.com/oxygene76/medas-notary-contract", tag: $tag, commit: $commit},
              from_height: $h}]}' \
   contract.json > contract.json.new && mv contract.json.new contract.json
jq -c '.networks' contract.json >&2
if [ -d "$WEB_REPO/node_modules" ]; then
	cat > check.mts <<TS
import { readFileSync } from "node:fs";
import { contractForNetwork, validateContractFile } from "$WEB_REPO/src/lib/contractfile";
const c = contractForNetwork(validateContractFile(JSON.parse(readFileSync("$WORK/contract.json", "utf8"))), "medasdigital-2")!;
if (c.address !== "$CONTRACT" || c.codeSha256 !== "$WASM_SHA256" || c.fromHeight !== $H) throw new Error(JSON.stringify(c));
console.log("   ok: the web app's validation accepts the entry", JSON.stringify(c));
TS
	(cd "$WEB_REPO" && npx tsx "$WORK/check.mts") >&2 || fail "contract.json entry not accepted by the web app"
fi

# ---------------------------------------------------------------- section 8
step "8. memo commits after the cut-off"
$MD q txs --query "transfer.recipient='medas1h5k8r0ll56nszczz3n6wh508qjljudmp5rclgk' AND tx.height>$H" $Q \
	| jq -r '.txs[] | .height + "  " + .txhash + "  " + .tx.body.memo' >&2
echo "   (none expected on a fresh localnet)" >&2

rm -rf "$WORK"
echo "PASS" >&2
