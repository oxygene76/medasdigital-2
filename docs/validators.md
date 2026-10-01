# Running a validator

The setup script never creates or imports keys. Do these steps yourself,
on the node, after it is fully synced.

Run every command in this guide as the user the node runs as
(NODE_USER, default root). If you set NODE_HOME, add
--home <NODE_HOME> to every command.

## 1. Wait until the node is synced

    ./medasdigital_setup.sh status        # "Catching up" must be false

Creating a validator on a node that is still catching up makes it miss
blocks right away.

## 2. Create or restore the operator wallet

These commands pass `--keyring-backend file` explicitly, so every
command uses the same encrypted keyring. Without the option, the
binary uses the backend set in `config/client.toml` ("os" by
default). That keyring lives in a different place, so a key
created one way is not found the other way. If your wallet
already exists in another backend, pass that backend instead.
Never use "test" on a server: it stores keys unencrypted. The
file backend asks for a passphrase.

    medasdigitald keys add <wallet> --keyring-backend file             # new wallet
    medasdigitald keys add <wallet> --recover --keyring-backend file   # restore from mnemonic
    medasdigitald keys show <wallet> -a --keyring-backend file         # account address

Write the mnemonic down offline. Never store it on the server.
For a dedicated node user, for example:
`sudo -u medas -H medasdigitald keys add <wallet> --keyring-backend file`.

## 3. Fund the wallet

Send enough MEDAS for your self-delegation plus fees to the address from
step 2.

## 4. Create the validator

    medasdigitald comet show-validator          # consensus public key

Create `validator.json`:

    {
      "pubkey": <output of comet show-validator>,
      "amount": "1000000umedas",
      "moniker": "<your-moniker>",
      "identity": "",
      "website": "",
      "security": "",
      "details": "",
      "commission-rate": "0.10",
      "commission-max-rate": "0.20",
      "commission-max-change-rate": "0.01",
      "min-self-delegation": "1"
    }

Submit it:

    medasdigitald tx staking create-validator validator.json \
      --from <wallet> --keyring-backend file --chain-id medasdigital-2 \
      --gas auto --gas-adjustment 1.5 --gas-prices 0.025umedas

Check:

    medasdigitald keys show <wallet> --bech val -a --keyring-backend file   # operator address (asks for the passphrase)
    medasdigitald q staking validator <operator-address>
    ./medasdigital_setup.sh status        # voting power > 0

## 5. Protect your keys

- `config/priv_validator_key.json` is your validator's signing key. Keep
  an offline, encrypted backup of it, of the wallet mnemonic and,
  optionally, of `config/node_key.json` (the node's P2P identity).
- **Never run the same `priv_validator_key.json` on two machines at the
  same time.** This is double signing: the validator is slashed and
  permanently removed (tombstoned). This includes clones, restored
  backups and VM snapshots that are started with network access, and
  standby nodes, even briefly during a move.
- Moving a validator: stop and disable the old node first and make sure
  it cannot start again, then start the new one.
- When moving a validator, copy `data/priv_validator_state.json`
  from the stopped old node together with the key. Never replace
  it with an older copy, for example from a backup.

## 6. After downtime

A validator that misses too many blocks is jailed. With the current
parameters, missing more than 50 % of the blocks in the signing window
jails the validator for 10 minutes and slashes 1 % of the stake; double
signing slashes 5 %. `medasdigitald query slashing params` shows the
current values. Plan maintenance, and never stop several validators at
the same time.

Once the node is running and synced again:

    medasdigitald tx slashing unjail --from <wallet> --keyring-backend file \
      --chain-id medasdigital-2 --gas auto --gas-adjustment 1.5 --gas-prices 0.025umedas

## Upgrades

Before every chain upgrade, follow the matching guide in
[docs/upgrades/](upgrades/).
