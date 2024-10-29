#!/bin/bash

# Define variables
REPO="https://github.com/oxygene76/medasdigital-2/releases"
BIN_DIR="/usr/local/bin"
NODE_HOME="$HOME/.medasdigital"
CHAIN_ID="medasdigital-2"

# Function to download and install the latest binary from GitHub
setup_node() {
    echo "Fetching latest MedasDigital binary..."
    # Fetch the latest release version
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/oxygene76/medasdigital-2/releases/latest" | grep "tag_name" | cut -d '"' -f 4)
    echo "Latest version: $LATEST_RELEASE"

    # Download the binary (adjust filename if needed)
    wget "$REPO/download/$LATEST_RELEASE/medasdigitald" -O medasdigitald
    chmod +x medasdigitald
    sudo mv medasdigitald $BIN_DIR/

    # Prompt for moniker name
    read -p "Enter your node moniker (name): " MONIKER_NAME

    # Initialize the node with custom moniker
    echo "Initializing node with moniker: $MONIKER_NAME"
    medasdigitald init "$MONIKER_NAME" --chain-id $CHAIN_ID
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
    if ! medasdigitald keys show $WALLET_NAME > /dev/null 2>&1; then
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
      --pubkey $(medasdigitald tendermint show-validator) \
      --moniker "$MONIKER_NAME" \
      --chain-id $CHAIN_ID
}

# Function to create a wallet
create_wallet() {
    read -p "Enter a wallet name: " WALLET_NAME
    medasdigitald keys add $WALLET_NAME
}

# Function to list wallets
list_wallets() {
    medasdigitald keys list
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

    case $choice in
        1) setup_node ;;
        2) setup_validator ;;
        3) create_wallet ;;
        4) list_wallets ;;
        5) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Please select a valid option [1-5].";;
    esac
done
