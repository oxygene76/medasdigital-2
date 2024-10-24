#!/bin/bash

# This script will set up a MedasDigital node on a Linux system

# Update and install required dependencies
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y build-essential git wget jq make gcc chrony

# Install Go (version 1.22 is required)
GO_VERSION="1.22.0"
wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm "go${GO_VERSION}.linux-amd64.tar.gz"

# Set Go environment variables
cat << EOF >> ~/.profile
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export GO111MODULE=on
export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin
EOF
source ~/.profile

go version  # Verify installation

# Clone the MedasDigital repository
git clone https://github.com/your-repo/medasdigital.git
cd medasdigital

# Build the MedasDigital binary
make install

# Initialize the node
medasdigitald init "<your-node-moniker>" --chain-id medasdigital-2

# Download the genesis file
wget -O ~/.medasdigitald/config/genesis.json https://raw.githubusercontent.com/your-repo/medasdigital/mainnet/genesis.json

# Configure seeds and persistent peers
SEEDS="<your-seed-nodes>"
PEERS="<your-persistent-peers>"
sed -i.bak -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" ~/.medasdigitald/config/config.toml

# Set minimum gas price
sed -i.bak 's/minimum-gas-prices =.*/minimum-gas-prices = "0.025umedas"/' ~/.medasdigitald/config/app.toml

# Set up the node as a systemd service
sudo tee /etc/systemd/system/medasdigitald.service > /dev/null <<EOF
[Unit]
Description=MedasDigital Node
After=network-online.target

[Service]
User=$USER
ExecStart=$(which medasdigitald) start
Restart=always
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable medasdigitald
sudo systemctl start medasdigitald

# Check service status
sudo systemctl status medasdigitald

# Output instructions
echo "Node setup complete. Use 'journalctl -fu medasdigitald' to monitor the logs."

