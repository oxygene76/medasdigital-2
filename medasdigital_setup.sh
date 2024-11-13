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
    medasdigitald init "MedasDigitalNode" --chain-id $CHAIN_ID --home $NODE_HOME

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
    read -p "Enter your wallet name: " WALLET_NAME
    read -p "Enter your staking amount (e.g., 1000000umedas): " STAKE_AMOUNT
    read -p "Enter your commission rate (e.g., 0.10): " COMMISSION_RATE
    read -p "Enter your commission max rate (e.g., 0.20): " COMMISSION_MAX_RATE
    read -p "Enter your commission max change rate (e.g., 0.01): " COMMISSION_MAX_CHANGE
    read -p "Enter your validator moniker (name): " MONIKER_NAME

    if ! medasdigitald keys show $WALLET_NAME --home $NODE_HOME > /dev/null 2>&1; then
        echo "Wallet $WALLET_NAME does not exist. Please create it first."
        exit 1
    fi

    echo "Creating validator with moniker: $MONIKER_NAME"
    medasdigitald tx staking create-validator \
      --amount $STAKE_AMOUNT \
      --from $WALLET_NAME \
      --commission-rate $COMMISSION_RATE \
      --commission-max-rate $COMMISSION_MAX_RATE \
      --commission-max-change-rate $COMMISSION_MAX_CHANGE \
      --min-self-delegation "1" \
      --pubkey $(medasdigitald tendermint show-validator --home $NODE_HOME) \
      --moniker "$MONIKER_NAME" \
      --chain-id $CHAIN_ID \
      --home $NODE_HOME
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
    echo "7) Exit"
    read -p "Enter your choice [1-7]: " choice

    case $choice in
        1) setup_node ;;
        2) setup_validator ;;
        3) create_wallet ;;
        4) import_wallet ;;
        5) list_wallets ;;
        6) create_service ;;
        7) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Please select a valid option [1-7]."; pause ;;
    esac
done
