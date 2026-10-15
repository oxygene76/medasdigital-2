# Runbook: Wasm-Upload per Gov-Proposal beschränken (medasdigital-2)

**Ziel:** Nur die Deploy-Adresse `medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv` darf
neuen CosmWasm-Code hochladen. Instanziieren bleibt für alle erlaubt. Die
Beschränkung ist eine Sofortmaßnahme gegen bekannte Schwachstellen in wasmvm 2.1.2,
SDK 0.50.10 und ibc-go 8.5.1.

- Proposal-Datei: [`proposals/wasm-upload-restriction.json`](../../proposals/wasm-upload-restriction.json),
  sha256 `0f9d3010ee123a250d3c08c40c2cb93257d2837c119a026abd492ad245b3e712`
- Rückweg: [`proposals/wasm-upload-unrestrict.json`](../../proposals/wasm-upload-unrestrict.json),
  sha256 `b8088aab787aed051dfdc4592a03bc6f28eb8c92c9530872451142b0c4e5a6ec`
- Auf dem Localnet mit dem Mainnet-Binary geprüft:
  `scripts/wasm-upload-restriction-test.sh`. Die Befehle dieses Runbooks wurden
  dort 1:1 durchgespielt (Abschnitt 9).

## 0. Ablauf und Zeitplan

| Schritt | Wer | Dauer |
|---|---|---|
| Einreichen mit 50 MEDAS Deposit (= `expedited_min_deposit`) | Proposer-Konto | sofort in der Voting Period |
| Abstimmen | Operator-Konto jedes Validators | so früh wie möglich |
| Expedited-Auszählung | Chain | **24 h** nach Einreichen |
| Ohne ≥ 66,7 % Ja nach 24 h: Umwandlung in normalen Proposal | Chain | Ende **48 h** nach Einreichen, Schwelle 50 % |

- Quorum: 33,4 % der gebondeten Stake. Veto-Schwelle: 33,4 %. Bei Veto wird der
  Deposit verbrannt (`burn_vote_veto = true`).
- Ohne Veto bekommt der Proposer den Deposit nach Ende der Abstimmung zurück.
- Die neue Einstellung gilt ab dem Block, in dem die Abstimmung endet. Ein
  Neustart ist nicht nötig.

## 1. Variablen (auf jedem Validator, als Benutzer des Nodes)

```sh
export NODE_HOME=<Home-Verzeichnis des Nodes, z. B. ~/.medasdigital>
# kein --node hier: "keys"-Befehle kennen das Flag nicht. Der RPC-Endpunkt kommt aus
# $NODE_HOME/config/client.toml (Standard tcp://localhost:26657), prüfen mit:
#   medasdigitald --home $NODE_HOME config get client node
export MD="medasdigitald --home $NODE_HOME"
export CHAIN_ID=medasdigital-2
# Gebühren: min-gas-price 0.025umedas; feste Gas-Werte, weil --gas auto bei Votes zu knapp schätzt
export TX_GOV="--chain-id $CHAIN_ID --gas 400000 --fees 10000umedas"
export TX_VOTE="--chain-id $CHAIN_ID --gas 200000 --fees 5000umedas"
export GOV=medas10d07y265gmmuvt4z0w9aw880jnsr700jl30dxf
export DEPLOY=medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv
```

Der Keyring-Backend ist laut Setup-Skript `file` (in `client.toml`). Bei jedem
`tx` wird deshalb die Keyring-Passphrase abgefragt.

## 2. Vorab-Prüfungen

```sh
# richtige Datei?
sha256sum wasm-upload-restriction.json      # -> 0f9d3010...b3e712
jq . wasm-upload-restriction.json           # authority = $GOV, addresses = [$DEPLOY], expedited = true

# Node synchron?
$MD status | jq '.sync_info | {latest_block_height, catching_up}'

# Gov-Adresse und Parameter wie erwartet?
$MD q auth module-account gov -o json | jq -r .account.value.address     # = $GOV
$MD q gov params -o json | jq '.params | {expedited_min_deposit, expedited_voting_period, expedited_threshold, voting_period}'
$MD q wasm params -o json                   # heute: Everybody / Everybody

# Welcher Code liegt schon auf der Chain? (bleibt instanziierbar)
$MD q wasm list-code -o json | jq '.code_infos[] | {code_id, creator}'

# Proposer-Konto: Adresse und Guthaben (>= 50 MEDAS + Gebühren)
export PROPOSER_KEY=<key-name>
export PROPOSER=$($MD keys show $PROPOSER_KEY -a)
$MD q bank balances $PROPOSER -o json
```

## 3. Einreichen

```sh
# Simulation ohne Broadcast (--dry-run braucht die Adresse, nicht den Key-Namen)
$MD tx gov submit-proposal wasm-upload-restriction.json --from $PROPOSER $TX_GOV --dry-run
# -> "gas estimate: ..." (Localnet: ca. 265 000, also unter den 400 000), keine Fehlermeldung

# Einreichen
$MD tx gov submit-proposal wasm-upload-restriction.json --from $PROPOSER_KEY $TX_GOV -y -o json | tee submit.json
# code muss 0 sein
jq '{code, txhash, raw_log}' submit.json
```

Proposal-ID ermitteln (einige Sekunden warten, bis die Transaktion im Block ist):

```sh
export ID=$($MD q tx $(jq -r .txhash submit.json) -o json \
  | jq -r '[.events[] | select(.type=="submit_proposal") | .attributes[] | select(.key=="proposal_id") | .value][0]')
echo $ID
```

## 4. Deposit und Status prüfen

```sh
$MD q gov proposal $ID -o json | jq '.proposal | {id, status, expedited, total_deposit, voting_start_time, voting_end_time}'
$MD q gov deposits $ID -o json
```

Erwartet:
- `status = PROPOSAL_STATUS_VOTING_PERIOD`, `expedited = true`
- `total_deposit = 50000000umedas`
- `voting_end_time` = Einreichzeit + 24 h

Steht der Status auf `PROPOSAL_STATUS_DEPOSIT_PERIOD`, fehlt Deposit. Nachlegen mit:

```sh
$MD tx gov deposit $ID <fehlender-betrag>umedas --from $PROPOSER_KEY $TX_VOTE -y
```

## 5. Abstimmen mit den Operator-Konten

Die Stimme eines Validators gibt das Konto ab, das den Validator angelegt hat,
also dessen Operator-Konto. Auf **jedem** Validator-Host:

```sh
# Key des Operator-Kontos finden: seine valoper-Adresse muss in der Validator-Liste stehen
$MD keys list
export OPERATOR_KEY=<key-name>
$MD keys show $OPERATOR_KEY --bech val -a
$MD q staking validators -o json | jq -r '.validators[] | .operator_address + "  " + .description.moniker'

# abstimmen
$MD tx gov vote $ID yes --from $OPERATOR_KEY $TX_VOTE -y -o json | jq '{code, txhash, raw_log}'

# Stimme prüfen
$MD q gov vote $ID $($MD keys show $OPERATOR_KEY -a) -o json
```

- Delegatoren, die selbst abstimmen, überschreiben die Stimme ihres Validators
  für ihren Anteil.
- Eine Stimme lässt sich bis zum Ende der Abstimmung mit einem neuen `vote` ändern.

## 6. Auszählung beobachten

```sh
$MD q gov tally $ID -o json
$MD q gov votes $ID -o json | jq -r '.votes[] | .voter + "  " + .options[0].option'
$MD q staking pool -o json      # bonded_tokens als Bezugsgröße für das Quorum
```

Für die Expedited-Annahme braucht es alle drei Bedingungen:
- Ja-Stimmen > 66,7 % der abgegebenen Stimmen ohne Enthaltungen,
- Beteiligung ≥ 33,4 % der gebondeten Stake,
- Veto < 33,4 %.

## 7. Kontrolle nach Annahme (ab `voting_end_time`)

```sh
$MD q gov proposal $ID -o json | jq -r .proposal.status        # PROPOSAL_STATUS_PASSED
$MD q wasm params -o json
# {"code_upload_access":{"permission":"AnyOfAddresses","addresses":["medas1rtpn4veps600g8p5nm8e7m4pcggvgqv5cw04tv"]},"instantiate_default_permission":"Everybody"}
```

Optionaler Negativtest ohne Kosten: eine Upload-Simulation von einer anderen
Adresse als `$DEPLOY` muss scheitern.

```sh
$MD tx wasm store <datei.wasm> --from $PROPOSER --chain-id $CHAIN_ID --dry-run
# Erwartet: Fehler "... can not create code: unauthorized"
```

Steht der Status stattdessen auf `PROPOSAL_STATUS_FAILED`, zeigt
`$MD q gov proposal $ID -o json | jq .proposal.failed_reason` den Grund. Dann bleibt
alles bei `Everybody`.

## 8. Rückweg: Upload wieder für alle freigeben

Erst nach dem Upgrade auf Versionen ohne die Schwachstellen einreichen. Dafür
reicht ein normaler Proposal: 10 MEDAS Deposit, 48 h Abstimmung, Schwelle 50 %.

```sh
sha256sum wasm-upload-unrestrict.json       # -> b8088aab...e5a6ec
$MD tx gov submit-proposal wasm-upload-unrestrict.json --from $PROPOSER --chain-id $CHAIN_ID --dry-run
$MD tx gov submit-proposal wasm-upload-unrestrict.json --from $PROPOSER_KEY $TX_GOV -y -o json | tee submit-rollback.json
# weiter wie Abschnitte 3-7; danach:
$MD q wasm params -o json      # Everybody / Everybody
```

Ist es schneller nötig, zum Beispiel weil die Deploy-Adresse verloren ist, kann
`"expedited": true` mit `"deposit": "50000000umedas"` gesetzt werden. Das ist eine
bewusste Abweichung von der geprüften Datei.

## 9. Localnet-Probe dieses Runbooks

- Durchgespielt mit dem Mainnet-Binary (`build/old`, Code von v1.0.1):
  - Chain-ID `medasdigital-local`, Node `tcp://127.0.0.1:36657` (in `client.toml`),
  - Keyring `test` statt `file` (in `client.toml`),
  - Deploy-Adresse `alice`, Expedited-Periode 20 s statt 24 h.
- Die Befehle der Abschnitte 2–8 liefen unverändert über dieselben Variablen.
- Die automatisierte Fassung ist `scripts/wasm-upload-restriction-test.sh`.
- Beobachtet:
  - Der Proposal war nach genau der Expedited-Periode `PASSED`.
  - Ein Upload von einer fremden Adresse scheiterte mit
    `failed to execute message; message index: 0: can not create code: unauthorized` (code 4).
  - Ein Upload von der Deploy-Adresse gelang. Der neue Code hat `instantiate_permission Everybody`.
  - Instanziieren des alten und des neuen Codes von einer fremden Adresse gelang.
  - Der Rückweg-Proposal stellte `Everybody` wieder her.

## 10. Was die Maßnahme nicht abdeckt

- **Gesperrt** sind `MsgStoreCode`, `MsgStoreAndInstantiateContract` und
  `MsgStoreAndMigrateContract` für alle außer `$DEPLOY`. Das gilt auch für
  Interchain Accounts, per authz beauftragte Konten und Contracts: geprüft wird
  immer der tatsächliche Absender.
- **Nicht gesperrt:**
  - Upload per Gov-Proposal (die Gov-Autorität umgeht die Beschränkung),
  - Instanziieren und Ausführen von bereits hochgeladenem Code,
  - Migrationen durch Contract-Admins auf vorhandenen Code.
  - Schwachstellen, die sich über vorhandene Contracts oder außerhalb von wasm
    (SDK, ibc-go) auslösen lassen, bleiben bis zum Software-Upgrade offen.
- Wird der Schlüssel der Deploy-Adresse kompromittiert, fällt die Schutzwirkung
  weg. Er gehört entsprechend gesichert, idealerweise auf eine Ledger-Hardware-Wallet.

## 11. Zweite Rolle der Deploy-Adresse: Contract-Admin des Notariats (Pilot)

Entscheidung vom 15.10.2026: Im Pilot ist `$DEPLOY` auch Contract-Admin des
Notariats-Contracts (`docs/notary-contract-spec.md` Abschnitt 9 und 10 auf
`feat/notary`). Das ist eine **bewusste Abweichung** von der Spezifikation, die
eine eigene, sonst unbenutzte Adresse vorsah.

- `$DEPLOY` lädt den Notariats-Code hoch, erlaubt die Instanziierung nur sich
  selbst und instanziiert mit `--admin` auf sich selbst:

  ```sh
  export DEPLOY_KEY=<key-name von $DEPLOY>   # auf dem Offline-Rechner, nicht auf einem Validator
  $MD tx wasm store medas_notary.wasm --from $DEPLOY_KEY --instantiate-anyof-addresses $DEPLOY ...
  $MD tx wasm instantiate <code_id> '<InstantiateMsg>' --label medas-notary --admin $DEPLOY --from $DEPLOY_KEY ...
  ```

  Danach kann nur `$DEPLOY` Parameter und Notariats-Admins ändern und den
  Contract migrieren.
- **Vorteil:** ein Schlüssel weniger. **Preis:** Verlust oder Kompromittierung
  trifft beide Rollen zugleich, den Code-Upload der ganzen Chain und die
  Kontrolle über das Notariat.
- Deshalb gilt für den Schlüssel von `$DEPLOY` zusätzlich zu Abschnitt 10:
  - **offline** aufbewahrt, nur für einen Upload, eine Instanziierung, eine
    Parameter- oder Admin-Änderung des Notariats oder eine Migration hervorgeholt;
  - **nie in einer Browser-Wallet** (Keplr, Leap) und nie über die Web-App des
    Notariats; signiert wird nur mit der CLI oder einem Ledger;
  - nie Notariats-Admin, Relayer- oder Validator-Schlüssel.
- **Nach dem Pilot** geht der Contract-Admin an Governance über
  (`MsgUpdateAdmin` auf `$GOV`). Damit endet die Doppelrolle; `$DEPLOY` bleibt
  nur Upload-Adresse, bis der Rückweg aus Abschnitt 8 den Upload wieder freigibt.
- Stand der Mainnet-Parameter am 15.10.2026 (Abfrage, keine Transaktion):
  `code_upload_access` = `AnyOfAddresses [$DEPLOY]`, Codes 1–3 von `$DEPLOY`.
