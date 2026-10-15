# Runbook: Go-Live des Notariats-Contracts auf medasdigital-2

**Ziel:** Der Notariats-Contract (`medas-notary` 0.2.0, Spezifikation
[`docs/notary-contract-spec.md`](../notary-contract-spec.md)) läuft auf
medasdigital-2 und ist in [`docs/notary/contract.json`](../notary/contract.json)
festgeschrieben. Danach gehen neue Einträge an den Contract; Phase 0 endet mit
dem Block der Instanziierung (Abschnitt 8).

Die Web-App und der Profil-Dienst werden danach umgestellt: `docs/operations.md`
im Repository medas-notary-web, Abschnitt „Go-live of contract mode on mainnet“.

| | |
|---|---|
| Release | `medas-notary-contract` Tag `v0.2.0`, Commit `25cd3e2ae5e8c14e3becea90576901a57e895f03` |
| Code-Hash (sha256 der `.wasm`) | `1487721ae59465653638cdae9e98fb1a2f45239381cca78a2013d49d47a13e76` |
| Upload-Adresse = Contract-Admin | `medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv` (Spezifikation Abschnitt 9) |
| Notariats-Admin | `medas1wg443w3st9mv05n68jklky5yzpn23ff09d8qf7` |
| Gebühr je Eintrag | 1.000 MEDAS (`1000000000umedas`), 100 % verbrannt |
| Startguthaben je Freigabe | 1.002 MEDAS (`1002000000umedas`) |
| `require_registration` | `true` |

**Schlüssel:** Upload und Instanziierung signiert die Upload-Adresse. Für den
Umgang mit ihrem Schlüssel gelten Abschnitt 10 und 11 von
[`docs/runbooks/wasm-upload-restriction.md`](https://github.com/oxygene76/medasdigital-2/blob/ops/wasm-upload-restriction/docs/runbooks/wasm-upload-restriction.md)
(Branch `ops/wasm-upload-restriction`): offline aufbewahrt, nie in einer
Browser-Wallet, nur mit der CLI oder einem Ledger, Übergabe des Contract-Admins
an Governance nach dem Pilot.

## 0. Ablauf

| Schritt | Wer | Abschnitt |
|---|---|---|
| Release prüfen (Hash, Tag, reproduzierbarer Build) | Operatoren | 2 |
| Vorab-Prüfungen auf der Chain | Operatoren | 3 |
| Code hochladen, Instanziierung nur für die Upload-Adresse | Upload-Adresse | 4 |
| Instanziieren mit `--admin` auf die Upload-Adresse | Upload-Adresse | 5 |
| Prüfungen nach der Instanziierung | Operatoren | 6 |
| Eintrag in `docs/notary/contract.json`, Festschreiben | Operatoren | 7 |
| Stichtag Phase 0 bekanntgeben | Operatoren | 8 |
| Web-App und Dienst umstellen, Probelauf | Operatoren | medas-notary-web `docs/operations.md` |

Gesamtkosten der Chain-Schritte: etwa 0,1 MEDAS Gebühren für die Upload-Adresse.
Die Instanziierung trägt keine Mittel.

## 1. Variablen

```sh
export MD=medasdigitald
export CHAIN_ID=medasdigital-2
export NODE=<RPC-Adresse eines vertrauenswürdigen, synchronen Nodes, z. B. tcp://localhost:26657>
export Q="--node $NODE -o json"
export TX="--node $NODE --chain-id $CHAIN_ID"
export DEPLOY=medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv
export DEPLOY_KEY=<Key-Name der Upload-Adresse>    # oder --ledger, siehe wasm-upload-restriction.md
export NOTARY_ADMIN=medas1wg443w3st9mv05n68jklky5yzpn23ff09d8qf7
export RELEASE=v0.2.0
export SOURCE_COMMIT=25cd3e2ae5e8c14e3becea90576901a57e895f03
export WASM_SHA256=1487721ae59465653638cdae9e98fb1a2f45239381cca78a2013d49d47a13e76
```

Gebühren: `minimum-gas-prices` ist `0.025umedas`. Die Befehle nennen feste
Gas-Werte mit Abstand zu den Messungen auf dem Localnet (Upload 2,58 Mio.,
Instanziierung 191.000).

## 2. Release prüfen

Auf einem Rechner mit Docker, unabhängig vom Rechner mit dem Schlüssel:

```sh
git clone https://github.com/oxygene76/medas-notary-contract
cd medas-notary-contract
git rev-parse "$RELEASE^{commit}"                   # = $SOURCE_COMMIT
git checkout "$RELEASE"

# veröffentlichte Datei aus dem GitHub-Release
curl -fsSLO "https://github.com/oxygene76/medas-notary-contract/releases/download/$RELEASE/medas_notary.wasm"
curl -fsSLO "https://github.com/oxygene76/medas-notary-contract/releases/download/$RELEASE/checksums.txt"
sha256sum medas_notary.wasm                         # = $WASM_SHA256
grep "$WASM_SHA256" checksums.txt

# reproduzierbarer Build (Optimizer-Image per Digest gepinnt, Rust 1.81.0)
scripts/build-release.sh                            # artifacts/medas_notary.wasm
sha256sum artifacts/medas_notary.wasm               # = $WASM_SHA256
```

- Ein zweiter Build durch eine andere Person oder auf einem anderen Rechner muss
  denselben Hash ergeben (Spezifikation Abschnitt 10.1).
- Der Hash steht auch in der Spezifikation (Abschnitt 6.2) dieses Repositorys.
- `scripts/localnet-check.sh` im Contract-Repository (Localnet mit dem
  Mainnet-Binary v2.0.0) muss mit `PASS` enden.

Weiter nur mit `medas_notary.wasm`, deren sha256 `$WASM_SHA256` ist.

## 3. Vorab-Prüfungen auf der Chain

```sh
$MD status --node $NODE | jq '.sync_info | {latest_block_height, catching_up}'     # catching_up false
$MD q wasm params $Q
# {"code_upload_access":{"permission":"AnyOfAddresses","addresses":["medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv"]},"instantiate_default_permission":"Everybody"}

# Ist dieser Code schon hochgeladen? (dann Abschnitt 4 auslassen und dessen code_id verwenden,
# sofern creator und instantiate_permission wie in Abschnitt 4 sind)
$MD q wasm list-code $Q | jq -c --arg h "${WASM_SHA256^^}" '.code_infos[] | select(.data_hash == $h) | {code_id, creator, instantiate_permission}'

# Guthaben der Upload-Adresse (mindestens 0,2 MEDAS)
$MD q bank balances $DEPLOY $Q | jq -c .balances

# Notariats-Admin ist eine gültige medas-Adresse (20 Byte)
$MD debug addr $NOTARY_ADMIN
```

**Phase 0 einfrieren:** Ab dem Block der Instanziierung zählen Memo-Commits
nicht mehr (Abschnitt 8). Vor der Instanziierung bekanntgeben, dass über die
alte Seite keine neuen Einträge mehr angelegt werden sollen, bis die Seite im
Contract-Modus läuft. Aufdecken bleibt möglich.

## 4. Code hochladen

Auf dem Rechner mit dem Schlüssel der Upload-Adresse, `medas_notary.wasm` aus
Abschnitt 2 (sha256 noch einmal prüfen):

```sh
sha256sum medas_notary.wasm                                   # = $WASM_SHA256

# Simulation ohne Broadcast (--dry-run braucht die Adresse, nicht den Key-Namen)
$MD tx wasm store medas_notary.wasm --from $DEPLOY $TX \
  --instantiate-anyof-addresses $DEPLOY --dry-run
# -> "gas estimate: ..." (Localnet: etwa 2,6 Mio.)

$MD tx wasm store medas_notary.wasm --from $DEPLOY_KEY $TX \
  --instantiate-anyof-addresses $DEPLOY \
  --gas 3500000 --fees 87500umedas -y -o json | tee store.json
jq '{code, txhash, raw_log}' store.json                         # code 0
```

Einige Sekunden warten, dann Code-ID und Prüfsumme aus der Transaktion lesen:

```sh
$MD q tx $(jq -r .txhash store.json) $Q > store-tx.json
jq '.code' store-tx.json                                        # 0
export CODE_ID=$(jq -r '[.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value][0]' store-tx.json)
echo $CODE_ID

$MD q wasm code-info $CODE_ID $Q | jq -c 'del(.data)'
```

Erwartet:
- `checksum` = `$WASM_SHA256` (in Großbuchstaben),
- `creator` = `$DEPLOY`,
- `instantiate_permission` = `{"permission":"AnyOfAddresses","addresses":["<$DEPLOY>"]}`.

Weicht etwas ab: **nicht instanziieren** (Abschnitt 9).

## 5. Instanziieren

Nachricht (Spezifikation Abschnitt 3.1) als Datei, damit sie geprüft werden kann:

```sh
cat > instantiate.json <<'JSON'
{
  "fee": { "denom": "umedas", "amount": "1000000000" },
  "fee_split": { "burn_bps": 10000, "community_pool_bps": 0, "recipients": [] },
  "start_credit": { "denom": "umedas", "amount": "1002000000" },
  "require_registration": true,
  "notary_admins": ["medas1wg443w3st9mv05n68jklky5yzpn23ff09d8qf7"]
}
JSON
jq -c . instantiate.json
# {"fee":{"denom":"umedas","amount":"1000000000"},"fee_split":{"burn_bps":10000,"community_pool_bps":0,"recipients":[]},"start_credit":{"denom":"umedas","amount":"1002000000"},"require_registration":true,"notary_admins":["medas1wg443w3st9mv05n68jklky5yzpn23ff09d8qf7"]}

# Simulation
$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label medas-notary --admin $DEPLOY \
  --from $DEPLOY $TX --dry-run

$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label medas-notary --admin $DEPLOY \
  --from $DEPLOY_KEY $TX --gas 300000 --fees 7500umedas -y -o json | tee instantiate-submit.json
jq '{code, txhash, raw_log}' instantiate-submit.json             # code 0
```

Einige Sekunden warten:

```sh
$MD q tx $(jq -r .txhash instantiate-submit.json) $Q > instantiate-tx.json
jq '.code' instantiate-tx.json                                  # 0
export CONTRACT=$(jq -r '[.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value][0]' instantiate-tx.json)
export INSTANTIATE_TX=$(jq -r .txhash instantiate-tx.json)
export H=$(jq -r .height instantiate-tx.json)                   # Stichtag Phase 0 (Abschnitt 8)
echo "$CONTRACT $INSTANTIATE_TX $H"
```

`instantiate.json`, `store-tx.json` und `instantiate-tx.json` aufbewahren.

## 6. Prüfungen nach der Instanziierung

```sh
S() { $MD q wasm contract-state smart $CONTRACT "$1" $Q | jq -c .data; }

$MD q wasm contract $CONTRACT $Q | jq -c '.contract_info | {code_id, creator, admin, label}'
# code_id = $CODE_ID, creator = admin = $DEPLOY, label "medas-notary"

$MD q wasm code-info $CODE_ID $Q | jq -r .checksum | tr A-F a-f   # = $WASM_SHA256

S '{"config":{}}'
# {"fee":{"denom":"umedas","amount":"1000000000"},"fee_split":{"burn_bps":10000,"community_pool_bps":0,"recipients":[]},
#  "start_credit":{"denom":"umedas","amount":"1002000000"},"require_registration":true,"commits":0,
#  "contract":"medas-notary","version":"0.2.0"}

S '{"notary_admins":{}}'
# genau medas1wg443w3st9mv05n68jklky5yzpn23ff09d8qf7 mit einem Zeitraum from_height = H + 1, until_height null

S "{\"notary_admin_at\":{\"address\":\"$NOTARY_ADMIN\",\"height\":$H}}"           # false (Änderungen gelten ab dem nächsten Block)
S "{\"notary_admin_at\":{\"address\":\"$NOTARY_ADMIN\",\"height\":$((H + 1))}}"   # true
S "{\"notary_admin_at\":{\"address\":\"$DEPLOY\",\"height\":$((H + 1))}}"         # false: der Contract-Admin ist kein Notariats-Admin

$MD q bank balances $CONTRACT $Q | jq -c .balances                                # []
```

Optional, ohne Kosten: Eine Instanziierung desselben Codes durch eine andere
Adresse muss scheitern (`--dry-run` mit einer beliebigen anderen Adresse):

```sh
$MD tx wasm instantiate $CODE_ID "$(jq -c . instantiate.json)" --label x --no-admin \
  --from <andere Adresse> $TX --dry-run
# Erwartet: Fehler "... can not instantiate: unauthorized"
```

Erst wenn alle Prüfungen stimmen, weiter mit Abschnitt 7.

## 7. Eintrag in `docs/notary/contract.json` und Festschreiben

Den Eintrag aus den Werten der Abschnitte 4 und 5 erzeugen, nicht von Hand
abtippen (Format: Spezifikation Abschnitt 10.5):

```sh
cd <Checkout von medasdigital-2, Branch feat/notary>
jq --arg addr "$CONTRACT" --arg tx "$INSTANTIATE_TX" --arg admin "$DEPLOY" \
   --argjson code "$CODE_ID" --arg sha "$WASM_SHA256" --arg tag "$RELEASE" --arg commit "$SOURCE_COMMIT" \
   --argjson h "$H" \
   '.networks["medasdigital-2"] = {address: $addr, instantiate_tx: $tx, contract_admin: $admin,
     codes: [{code_id: $code, code_sha256: $sha,
              source: {repository: "https://github.com/oxygene76/medas-notary-contract", tag: $tag, commit: $commit},
              from_height: $h}]}' \
   docs/notary/contract.json > contract.json.new && mv contract.json.new docs/notary/contract.json
git diff docs/notary/contract.json
git add docs/notary/contract.json
git commit -m "notary: contract on medasdigital-2 (code $CODE_ID, instantiated at height $H)"
```

**Festschreiben** (im Repository medas-notary-web, Einzelheiten dort in
`docs/operations.md`):

```sh
npm run contract -- --commit <Commit aus dem Schritt oben>   # pinnt config/contract.json
npm test                                                       # Format, Pin, Commit auf feat/notary
scripts/tag-pin.sh contract                                    # Tag notary-contract-<n> in medasdigital-2
```

Danach `feat/notary` und den Tag veröffentlichen (explizite Refspecs), bevor
die neue Seite live geht: Die Seite verweist auf diesen Commit.

## 8. Stichtag Phase 0

- Stichtag ist die Höhe `H` der Instanziierung. Sie steht in
  `docs/notary/contract.json` als `from_height` des ersten Codes.
- Memo-Commits bis einschließlich Block `H` bleiben Einträge und können
  weiterhin per Memo aufgedeckt werden, auch später.
- Memo-Commits nach Block `H` sind keine Einträge; die Web-App listet sie nicht
  (Spezifikation Abschnitt 11).
- Nach der Umstellung der Seite prüfen, ob zwischen `H` und der Umstellung noch
  Memo-Commits angelegt wurden, und die Betroffenen informieren:

  ```sh
  $MD q txs --query "transfer.recipient='medas1h5k8r0ll56nszczz3n6wh508qjljudmp5rclgk' AND tx.height>$H" $Q \
    | jq -r '.txs[] | .height + "  " + .txhash + "  " + .tx.body.memo'
  ```

## 9. Fehlerfälle und Rückweg

- **Falscher Code hochgeladen** (Prüfsumme, Ersteller oder
  Instanziierungsrecht falsch): nicht instanziieren. Code lässt sich nicht
  löschen; ist er nur für `$DEPLOY` instanziierbar, kann ihn niemand sonst
  verwenden. Mit der richtigen Datei Abschnitt 4 wiederholen.
- **Falscher Parameter nach der Instanziierung** (Gebühr, Aufteilung,
  Startguthaben, `require_registration`): `UpdateParams` durch `$DEPLOY`
  (Spezifikation 3.2). Die Denom lässt sich nicht ändern.
- **Falscher Notariats-Admin:** `SetNotaryAdmin` durch `$DEPLOY` (wirkt ab dem
  nächsten Block).
- **Falscher Contract-Admin, falscher Code oder falsches Label:** Instanz nicht
  verwenden und nicht in `contract.json` eintragen; neu instanziieren. Der
  Stichtag ist dann die Höhe der gültigen Instanziierung.
- Solange `contract.json` keinen Eintrag für medasdigital-2 hat, bleibt die
  Seite in Phase 0: Ein Fehler vor Abschnitt 7 ändert für Nutzer nichts.

## 10. Localnet-Probe dieses Runbooks

`scripts/notary-golive-rehearsal.sh` spielt die Abschnitte 3 bis 7 mit dem
Mainnet-Binary (`build/release/medasdigitald`, v2.0.0) auf einem frischen
Localnet durch: mit derselben Upload-Beschränkung wie auf Mainnet (per
Gov-Proposal gesetzt), mit `alice` als Upload-Adresse, `bob` als
Notariats-Admin und der Release-Datei aus medas-notary-contract. Die Befehle
laufen über dieselben Variablen wie oben; abweichend sind nur Chain-ID, Node,
Keyring `test` und die beiden Adressen.
