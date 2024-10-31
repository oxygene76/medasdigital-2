#!/bin/bash

# Define variables
REPO="https://github.com/oxygene76/medasdigital-2/releases"
BIN_DIR="/usr/local/bin"
NODE_HOME="$HOME/.medasdigital"   # Define node home directory
CHAIN_ID="medasdigital-2"
MIN_GAS_PRICE="0.025"             # Set the minimum gas price here
GAS_DENOM="umedas"                # Set the denom here
PERSISTENT_PEERS="peer1@ip1:26656,peer2@ip2:26656"  # Add your persistent peers here

# Function to download and install the latest binary from GitHub and set up CosmWasm library
setup_node() {
    echo "Fetching latest MedasDigital binary..."
    # Fetch the latest release version
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/oxygene76/medasdigital-2/releases/latest" | grep "tag_name" | cut -d '"' -f 4)
    echo "Latest version: $LATEST_RELEASE"

    # Download the binary
    wget "$REPO/download/$LATEST_RELEASE/medasdigitald" -O medasdigitald
    chmod +x medasdigitald
    sudo mv medasdigitald $BIN_DIR/

    # Set up CosmWasm library
    echo "Setting up CosmWasm library..."
    wget -P /usr/lib https://github.com/CosmWasm/wasmvm/raw/main/internal/api/libwasmvm.x86_64.so
    sudo ldconfig
    echo "CosmWasm library setup complete."

    # Initialize the node with the specified home directory
    echo "Initializing node in $NODE_HOME..."
    medasdigitald init "MedasDigitalNode" --chain-id $CHAIN_ID --home $NODE_HOME

    # Set minimum gas price and denom in app.toml
    echo "Setting minimum gas price and denom in app.toml..."
    sed -i "s/^minimum-gas-prices =.*/minimum-gas-prices = \"$MIN_GAS_PRICE$GAS_DENOM\"/" $NODE_HOME/config/app.toml

    # Set persistent peers and other configurations in config.toml
    echo "Setting persistent peers and other configurations in config.toml..."
    sed -i "s/^persistent_peers =.*/persistent_peers = \"$PERSISTENT_PEERS\"/" $NODE_HOME/config/config.toml

    echo "Node setup complete. Configuration is located in $NODE_HOME"
}

# Function to set up a validator
setup_validator() {
    read -p "Enter your wallet name: " WALLET_NAME
    read -p "Enter your staking amount (e.g., 1000000umedas): " STAKE_AMOUNT
    read -p "Enter your commission rate (e.g., 0.10): " COMMISSION_RATE
    read -p "Enter your commission max rate (e.g., 0.20): " COMMISSION_MAX_RATE
    read -p "Enter your commission max change rate (e.g., 0.01): " COMMISSION_MAX_CHANGE
    read -p "Enter your validator moniker (name): " MONIKER_NAME

    # Check if wallet exists
    if ! medasdigitald keys show $WALLET_NAME --home $NODE_HOME > /dev/null 2>&1; then
        echo "Wallet $WALLET_NAME does not exist. Please create it first."
        exit 1
    fi

    # Create validator with custom moniker
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
}

# Function to create a wallet
create_wallet() {
    read -p "Enter a wallet name: " WALLET_NAME
    medasdigitald keys add $WALLET_NAME --home $NODE_HOME
}

# Function to list wallets
list_wallets() {
    medasdigitald keys list --home $NODE_HOME
}

# Display menu
while true; do
    echo "Select an option:"
    echo "1) Setup Node"
    echo "2) Setup Validator"
    echo "3) Create Wallet"
    echo "4) List Wallets"
    echo "5) Exit"
    read -p "Enter your choice [1-5]: " choice

    case $choice
