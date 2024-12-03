#!/bin/bash

# Define variables
REPO="https://github.com/oxygene76/medasdigital-2/releases"
BIN_DIR="/usr/local/bin"
NODE_HOME="$HOME/.medasdigital"   # Define node home directory
CHAIN_ID="medasdigital-2"
MIN_GAS_PRICE="0.025"             # Set the minimum gas price here
GAS_DENOM="umedas"                # Set the denom here
PERSISTENT_PEERS="51ca3b0a3663af88566b32ecfd77948e55000bcc@88.205.101.195:26656,90be2e9f0a279372d2931e38f15025db9a847dbd@88.205.101.196:26656,0e567c9efe6e6d15f9b3257679398368c2ab04bb@88.205.101.197:26656,669d1b9f9c4bb99df594abaee4b13ae1b14d37a6@64.251.18.192:26656,cbfcd111ee19483dbbfed0919ac0d23119c5f0fe@67.207.180.166:26656"  # Add your persistent peers here
GENESIS_URL="https://raw.githubusercontent.com/oxygene76/medasdigital-2/refs/heads/main/genesis/mainnet/config/genesis.json"

# Funktion, um nach jeder Aktion auf Eingabe zu warten
pause() {
    read -p "Press Return to continue..."
}
# Function to download and install the latest binary from GitHub and set up CosmWasm library
setup_node() {
    clear
    if [ -d "$NODE_HOME" ]; then
        echo "Node has already been set up at $NODE_HOME."
        echo "Checking synchronization status..."
        SYNC_STATUS=$(medasdigitald status 2>&1 | jq -r '.sync_info.catching_up')
        CURRENT_BLOCK=$(medasdigitald status 2>&1 | jq -r '.sync_info.latest_block_height')
        if [ "$SYNC_STATUS" == "false" ]; then
            echo "Node is fully synchronized. Current block height: $CURRENT_BLOCK"
        else
            echo "Node is still synchronizing. Current block height: $CURRENT_BLOCK"
        fi
        pause
        return
    fi

    echo "Fetching latest MedasDigital binary..."
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/oxygene76/medasdigital-2/releases/latest" | grep "tag_name" | cut -d '"' -f 4)
    echo "Latest version: $LATEST_RELEASE"

    wget "$REPO/download/$LATEST_RELEASE/medasdigitald" -O medasdigitald
    chmod +x medasdigitald
    sudo mv medasdigitald $BIN_DIR/

    echo "Setting up CosmWasm library..."
    rm /usr/lib/libwasmvm.x86_64.so
    wget -P /usr/lib https://github.com/CosmWasm/wasmvm/releases/download/v2.1.2/libwasmvm.x86_64.so
    sudo ldconfig
    echo "CosmWasm library setup complete."

    echo "Initializing node in $NODE_HOME..."
    read -p "Enter your desired node moniker: " NODE_MONIKER
    medasdigitald init "$NODE_MONIKER" --chain-id $CHAIN_ID --home $NODE_HOME

    echo "Downloading genesis.json from $GENESIS_URL..."
    wget -O $NODE_HOME/config/genesis.json $GENESIS_URL
    echo "Genesis file downloaded and set up at $NODE_HOME/config/genesis.json."

    echo "Setting minimum gas price and denom in app.toml..."
    sed -i "s/^minimum-gas-prices =.*/minimum-gas-prices = \"$MIN_GAS_PRICE$GAS_DENOM\"/" $NODE_HOME/config/app.toml

    echo "Setting persistent peers and other configurations in config.toml..."
    sed -i "s/^persistent_peers =.*/persistent_peers = \"$PERSISTENT_PEERS\"/" $NODE_HOME/config/config.toml

    echo "Setting keyring-backend to file in client.toml..."
    sed -i "s/^keyring-backend =.*/keyring-backend = \"file\"/" $NODE_HOME/config/client.toml

    echo "Node setup complete. Configuration is located in $NODE_HOME"

    echo "Checking if the node is fully synchronized..."
    while true; do
        SYNC_STATUS=$(medasdigitald status 2>&1 | jq -r '.sync_info.catching_up')
        CURRENT_BLOCK=$(medasdigitald status 2>&1 | jq -r '.sync_info.latest_block_height')
        if [ "$SYNC_STATUS" == "false" ]; then
            echo "Node is fully synchronized. Setup complete."
            break
        else
            echo "Node is still synchronizing. Current block height: $CURRENT_BLOCK"
            sleep 10
        fi
    done
    pause
}

# Function to create a systemd service for the node
create_service() {
    clear
    echo "Creating systemd service for medasdigitald..."

    sudo tee /etc/systemd/system/medasdigitald.service > /dev/null <<EOF

[Unit]
Description=Medas Digital Node
After=network-online.target

[Service]
User=root
ExecStart=$BIN_DIR/medasdigitald start --home $NODE_HOME
Restart=always
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable medasdigitald
    echo "Service created and enabled. You can start it with: sudo systemctl start medasdigitald"
    pause
}

# Function to set up a validator
setup_validator() {
    clear

    if ! medasdigitald keys list --home $NODE_HOME | grep -q "name"; then
        echo "No wallet found. Creating a new wallet."
        read -p "Enter a wallet name: " WALLET_NAME
        medasdigitald keys add $WALLET_NAME --home $NODE_HOME
    else
        echo "Wallet found. Proceeding with validation setup."
        WALLET_NAME=$(medasdigitald keys list --home $NODE_HOME | grep "name" | awk '{print $2}')
    fi

    echo "Please make sure you have enough Medas tokens in the wallet for self-delegation."
    WALLET_ADDRESS=$(medasdigitald keys show $WALLET_NAME -a --home $NODE_HOME)
    BALANCE_OUTPUT=$(medasdigitald q bank balances $WALLET_ADDRESS --home $NODE_HOME)
    echo "Current wallet balance:"
    echo "$BALANCE_OUTPUT"
    read -p "Enter the amount of tokens to self-delegate (e.g., 1000000umedas) [default: 1000000umedas]: " STAKE_AMOUNT
    if [ -z "$STAKE_AMOUNT" ]; then
        STAKE_AMOUNT="1000000umedas"
    fi

    read -p "Enter your desired commission rate (e.g., 0.10) [default: 0.10]: " COMMISSION_RATE
    COMMISSION_RATE=${COMMISSION_RATE:-0.10}

    read -p "Enter your commission max rate (e.g., 0.20) [default: 0.20]: " COMMISSION_MAX_RATE
    COMMISSION_MAX_RATE=${COMMISSION_MAX_RATE:-0.20}

    read -p "Enter your commission max change rate (e.g., 0.01) [default: 0.01]: " COMMISSION_MAX_CHANGE
    COMMISSION_MAX_CHANGE=${COMMISSION_MAX_CHANGE:-0.01}

    MONIKER=$(grep '^moniker' $NODE_HOME/config/config.toml | cut -d '=' -f2 | sed 's/^ *//;s/ *$//' | tr -d '"')
    PUBKEY=$(medasdigitald tendermint show-validator --home $NODE_HOME | jq -r '.value')
    
    echo "########################################"
    echo "#        VALIDATOR CONFIGURATION       #"
    echo "########################################"
    echo "Moniker                : $MONIKER"
    echo "Wallet Name            : $WALLET_NAME"
    echo "Self-Delegation Amount : $STAKE_AMOUNT"
    echo "Commission Rate        : $COMMISSION_RATE"
    echo "Commission Max Rate    : $COMMISSION_MAX_RATE"
    echo "Commission Max Change  : $COMMISSION_MAX_CHANGE"
    echo "Public Key             : $PUBKEY"
    echo "########################################"
    echo

    read -p "Do you want to proceed with creating the validator? (yes/no): " CONFIRM
    if [[ $CONFIRM != "yes" ]]; then
        echo "Validator creation aborted."
        pause
        return
    fi
    
    echo "Creating validator JSON configuration..."
    VALIDATOR_JSON="$NODE_HOME/validator.json"
    
cat > $VALIDATOR_JSON <<EOF
    {
        "pubkey": {"@type": "/cosmos.crypto.ed25519.PubKey", "key": "$PUBKEY"},
        "amount": "$STAKE_AMOUNT",
        "moniker": "$MONIKER",
        "commission-rate": "$COMMISSION_RATE",
        "commission-max-rate": "$COMMISSION_MAX_RATE",
        "commission-max-change-rate": "$COMMISSION_MAX_CHANGE"
    }
EOF

    echo "Creating validator with moniker: $MONIKER"
    medasdigitald tx staking create-validator $VALIDATOR_JSON --from $WALLET_NAME --chain-id $CHAIN_ID -fees 5000umedas --gas-prices 0.025umedas --gas auto --home $NODE_HOME
    pause
}

# Function to create a wallet
create_wallet() {
    clear
    read -p "Enter a wallet name: " WALLET_NAME
    medasdigitald keys add $WALLET_NAME --home $NODE_HOME
    pause
}

# Function to import a wallet from mnemonic or private key
import_wallet() {
    clear
    read -p "Enter the wallet name: " WALLET_NAME
    echo "Choose import method:"
    echo "1) Mnemonic Phrase"
    echo "2) Private Key"
    read -p "Select an option [1-2]: " method

    if [[ $method -eq 1 ]]; then
        read -sp "Enter your 24-word mnemonic phrase: " MNEMONIC
        echo
        echo "Importing wallet from mnemonic..."
        echo "$MNEMONIC" | medasdigitald keys add $WALLET_NAME --recover --home $NODE_HOME
    elif [[ $method -eq 2 ]]; then
        read -sp "Enter your private key: " PRIVATE_KEY
        echo
        echo "Importing wallet from private key..."
        echo "$PRIVATE_KEY" | medasdigitald keys unsafe-import-eth-key $WALLET_NAME --home $NODE_HOME
    else
        echo "Invalid option. Please select either 1 or 2."
    fi
    pause
}

# Function to list wallets
list_wallets() {
    clear
    medasdigitald keys list --home $NODE_HOME
    pause
}

# Function to view node logs
view_node_logs() {
    clear
    echo "Displaying MedasDigital node logs..."
    sudo journalctl -fu medasdigitald
    pause
}

# Function to display node status including block height, peers, etc.
view_node_status() {
    clear  # Clear screen initially
    echo "Press [ESC] to exit."
    tput civis  # Hide cursor
    while true; do
        tput cup 0 0  # Move cursor to the top-left without clearing the screen
        SYNC_STATUS=$(medasdigitald status 2>&1 | jq -r '.sync_info.catching_up')
        CURRENT_BLOCK=$(medasdigitald status 2>&1 | jq -r '.sync_info.latest_block_height')
        PEERS=$(medasdigitald status 2>&1 | jq -r '.node_info.other.rpc_address')
        LATEST_BLOCK_INFO=$(medasdigitald q block $CURRENT_BLOCK 2>/dev/null)
        VALIDATOR_ADDRESS=$(echo "$LATEST_BLOCK_INFO" | jq -r '.block.last_commit.signatures[0].validator_address')
        if [ "$VALIDATOR_ADDRESS" != "null" ]; then
            VALIDATOR_INFO=$(medasdigitald q staking validator $VALIDATOR_ADDRESS 2>/dev/null)
            VALIDATOR_MONIKER=$(echo "$VALIDATOR_INFO" | jq -r '.description.moniker')
        else
            VALIDATOR_ADDRESS="N/A"
            VALIDATOR_MONIKER="N/A"
        fi

        echo "########################################"
        echo "#           NODE STATUS                #"
        echo "########################################"
        echo
        if [ "$SYNC_STATUS" == "false" ]; then
            echo "Node Status     : Fully Synchronized"
        else
            echo "Node Status     : Synchronizing"
        fi
        echo "Current Block   : $CURRENT_BLOCK"
        echo "Connected Peers : $PEERS"
        echo "Last Block Validator Address : ${VALIDATOR_ADDRESS}"
        echo "Last Block Validator Moniker : ${VALIDATOR_MONIKER}"
        echo "########################################"
        echo

        # Wait for 1 second or until ESC key is pressed
        read -t 1 -n 1 key
        if [[ $key == $'\e' ]]; then
            tput cnorm  # Show cursor
            break
        fi
    done
    tput cnorm  # Show cursor
    pause
}

# Display menu
while true; do
    clear

    # ASCII Banner
    echo "'##::::'##:'########:'########:::::'###:::::'######::                                          "
    echo " ###::'###: ##.....:: ##.... ##:::'## ##:::'##... ##:                                          "
    echo " ####'####: ##::::::: ##:::: ##::'##:. ##:: ##:::..::                                          "
    echo " ## ### ##: ######::: ##:::: ##:'##:::. ##:. ######::                                          "
    echo " ##. #: ##: ##...:::: ##:::: ##: #########::..... ##:                                          "
    echo " ##:.:: ##: ##::::::: ##:::: ##: ##.... ##:'##::: ##:                                          "
    echo " ##:::: ##: ########: ########:: ##:::: ##:. ######::                                          "
    echo "..:::::..::........::........:::..:::::..:::......:::                                          "
    echo "'########::'####::'######:::'####:'########::::'###::::'##:::::::::::'#######:::::::::'#####:::"
    echo " ##.... ##:. ##::'##... ##::. ##::... ##..::::'## ##::: ##::::::::::'##.... ##:::::::'##.. ##::"
    echo " ##:::: ##:: ##:: ##:::..:::: ##::::: ##:::::'##:. ##:: ##::::::::::..::::: ##::::::'##:::: ##:"
    echo " ##:::: ##:: ##:: ##::'####:: ##::::: ##::::'##:::. ##: ##:::::::::::'#######::::::: ##:::: ##:"
    echo " ##:::: ##:: ##:: ##::: ##::: ##::::: ##:::: #########: ##::::::::::'##::::::::::::: ##:::: ##:"
    echo " ##:::: ##:: ##:: ##::: ##::: ##::::: ##:::: ##.... ##: ##:::::::::: ##::::::::'###:. ##:: ##::"
    echo " ########::'####:. ######:::'####:::: ##:::: ##:::: ##: ########:::: #########: ###::. #####:::"
    echo "........:::....:::......::::....:::::..:::::..:::::..::........:::::.........::...::::.....::::"
    echo
    echo "Welcome to Medas Digital 2.0!"
    echo
    echo
    echo "Select an option:"
    echo "1) Setup Node"
    echo "2) Setup Validator"
    echo "3) Create Wallet"
    echo "4) Import Wallet"
    echo "5) List Wallets"
    echo "6) Create Systemd Service"
    echo "7) View Node Logs"
    echo "8) View Node Status"
    echo "9) Exit"
    read -p "Enter your choice [1-9]: " choice

    case $choice in
        1) setup_node ;;
        2) setup_validator ;;
        3) create_wallet ;;
        4) import_wallet ;;
        5) list_wallets ;;
        6) create_service ;;
        7) view_node_logs ;;
        8) view_node_status ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Please select a valid option [1-9]."; pause ;;
    esac
done
