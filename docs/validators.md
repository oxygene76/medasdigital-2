# Running a validator

The setup script never creates or imports keys. Do these steps yourself,
on the node, after it is fully synced.

## 1. Wait until the node is synced

    ./medasdigital_setup.sh status        # "Catching up: false"

Creating a validator on a node that is still catching up makes it miss
blocks right away.

## 2. Create or restore the operator wallet

The keyring uses the "file" backend and asks for a passphrase.

    medasdigitald keys add <wallet>             # new wallet
    medasdigitald keys add <wallet> --recover   # restore from mnemonic
    medasdigitald keys show <wallet> -a         # account address

Write the mnemonic down offline. Never store it on the server.
If the node runs as a dedicated user (NODE_USER), run these commands as
that user, for example `sudo -u medas -H medasdigitald keys add <wallet>`.

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
      --from <wallet> --chain-id medasdigital-2 \
      --gas auto --gas-adjustment 1.5 --gas-prices 0.025umedas

Check:

    medasdigitald q staking validator $(medasdigitald keys show <wallet> --bech val -a)
    ./medasdigital_setup.sh status        # voting power > 0

## 5. Protect your keys

- `config/priv_validator_key.json` is your validator's signing key. Keep
  an offline backup.
- **Never run the same `priv_validator_key.json` on two machines at the
  same time.** This is double signing: the validator is slashed and
  permanently removed (tombstoned). This includes clones, restored
  backups and VM snapshots that are started with network access.
- Moving a validator: stop and disable the old node first and make sure
  it cannot start again, then start the new one.
- `data/priv_validator_state.json` stays on the node and must never be
  replaced with an older copy.

## 6. After downtime

A validator that misses too many blocks is jailed. Once the node is
running and synced again:

    medasdigitald tx slashing unjail --from <wallet> \
      --chain-id medasdigital-2 --gas auto --gas-adjustment 1.5 --gas-prices 0.025umedas
