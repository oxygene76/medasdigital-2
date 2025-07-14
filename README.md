 # Welcome to MedasDigital 2.0: Building the Future of Decentralized Finance and Digital Ownership

MedasDigital 2.0 is an innovative blockchain project built on the Cosmos SDK, designed to empower users with a decentralized platform for finance, asset creation, and ownership. With a focus on security, flexibility, and ease of use, MedasDigital 2.0 is set to redefine how individuals and businesses engage with blockchain technology.

## Key Features of MedasDigital 2.0

- **Token Creation and Management**: MedasDigital 2.0 allows users to easily create, issue, and manage custom tokens. Whether for personal, business, or community purposes, our platform offers a streamlined experience for tokenization.
- **NFT Functionality**: Supporting the full life cycle of Non-Fungible Tokens (NFTs), MedasDigital 2.0 enables users to create, trade, and manage digital assets. From art to collectibles, MedasDigital 2.0 provides a secure and scalable environment for digital ownership.
- **Smart Contracts and WASM Support**: Our WASM integration supports smart contracts, enabling advanced functionalities for decentralized applications (dApps) and allowing developers to bring their unique ideas to life on a robust, secure blockchain.
- **Enhanced Security and Decentralization**: Built with the Cosmos SDK, MedasDigital 2.0 leverages Tendermint’s consensus engine, offering a high-performance, secure network. The platform’s design encourages decentralization, creating a resilient ecosystem supported by a global community of validators and node operators.
- **Community-Focused Governance**: MedasDigital 2.0 empowers its community with governance features, allowing token holders to influence network upgrades and policies directly. Through transparent and decentralized decision-making, MedasDigital 2.0 ensures that the community remains at the heart of the project’s evolution.

## A Growing Ecosystem with Real-World Use Cases

MedasDigital 2.0 is more than a blockchain; it’s a thriving ecosystem designed to bring real-world applications to decentralized finance (DeFi), digital ownership, and beyond. With support for token creation, NFTs, and smart contracts, MedasDigital 2.0 provides an ideal environment for developers, entrepreneurs, and community members to innovate and grow.

Join us as we build the future of blockchain technology. MedasDigital 2.0 is committed to creating a decentralized, user-centric platform that unlocks new possibilities in digital ownership and finance. Whether you’re a developer, validator, or simply a blockchain enthusiast, there’s a place for you in the MedasDigital 2.0 ecosystem.

-----

## MedasDigital 2.0 Launch: A Phased Validator and Node Approach

To ensure a stable and seamless start, we’re launching MedasDigital 2.0 with a set of our own initial validators. This approach allows us to closely monitor network stability, optimize performance, and ensure a secure environment for all participants.

### Why Start with Our Own Validators?

- **Stability and Reliability**: By beginning with our own validators, we maintain complete control over network stability during the critical early phase, minimizing potential issues.
- **Security Optimization**: Launching with our validators allows us to monitor security metrics closely and make any necessary adjustments before opening the network to external participants.
- **Gradual Decentralization**: Shortly after launch, we’ll expand validator and node access, enabling community members to join and contribute to network growth.

-----

## Node Setup Guide

This comprehensive guide will help you set up a MedasDigital 2.0 node from scratch, including compilation, service integration, and validator creation.

### Prerequisites

Before starting, ensure your system meets the following requirements:

- Ubuntu 20.04 LTS or later (or compatible Linux distribution)
- Minimum 4 GB RAM (8 GB recommended)
- 100 GB+ available disk space
- Stable internet connection
- Go 1.21+ installed

### Step 1: Install Dependencies

First, update your system and install the necessary dependencies:

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y build-essential git curl wget jq

# Install Go (if not already installed)
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export GOBIN=$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc

# Verify Go installation
go version
```

### Step 2: Clone and Compile MedasDigital

Clone the repository and compile the node binary:

```bash
# Clone the repository
git clone https://github.com/oxygene76/medasdigital-2.git
cd medasdigital-2

# Build the binary
make build

# Install the binary to system path
sudo cp build/medasdigitald /usr/local/bin/

# Verify installation
medasdigitald version
```

### Step 3: Initialize the Node

Set up your node configuration:

```bash
# Set node name (replace with your preferred name)
MONIKER="your-node-name"

# Initialize the node
medasdigitald init $MONIKER --chain-id medasdigital-2

# Create necessary directories
mkdir -p ~/.medasdigital/config
mkdir -p ~/.medasdigital/data
```

### Step 4: Configure Genesis and Network Settings

Download and configure the genesis file and network settings:

```bash
# Download genesis file (replace URL with actual genesis file location)
wget -O ~/.medasdigital/config/genesis.json https://raw.githubusercontent.com/oxygene76/medasdigital-2/main/genesis.json

# Configure peers and seeds (replace with actual peer information)
SEEDS="seed1@ip:port,seed2@ip:port"
PEERS="peer1@ip:port,peer2@ip:port"

# Update config.toml
sed -i "s/seeds = \"\"/seeds = \"$SEEDS\"/" ~/.medasdigital/config/config.toml
sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" ~/.medasdigital/config/config.toml

# Configure app.toml for optimal performance
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.001umedas"/' ~/.medasdigital/config/app.toml
```

### Step 5: Create Systemd Service

Create a systemd service to manage your node:

```bash
# Create the service file
sudo tee /etc/systemd/system/medasdigital.service > /dev/null <<EOF
[Unit]
Description=MedasDigital Node
After=network-online.target

[Service]
User=$USER
ExecStart=/usr/local/bin/medasdigitald start --home $HOME/.medasdigital
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable medasdigital
```

### Step 6: Start the Node

Start your node and monitor its status:

```bash
# Start the service
sudo systemctl start medasdigital

# Check service status
sudo systemctl status medasdigital

# Monitor logs in real-time
journalctl -u medasdigital -f

# Check sync status
medasdigitald status | jq .SyncInfo
```

### Step 7: Create a Wallet

Create a new wallet for your node operations:

```bash
# Create a new wallet (replace 'wallet-name' with your preferred name)
medasdigitald keys add wallet-name

# Or import an existing wallet
medasdigitald keys add wallet-name --recover

# List all wallets
medasdigitald keys list

# Check wallet balance
medasdigitald query bank balances $(medasdigitald keys show wallet-name -a)
```

### Step 8: Create a Validator

Once your node is fully synchronized, you can create a validator:

```bash
# Check if node is synchronized
medasdigitald status | jq .SyncInfo.catching_up

# Create validator transaction (adjust values as needed)
medasdigitald tx staking create-validator \
  --amount 1000000umedas \
  --pubkey $(medasdigitald tendermint show-validator) \
  --moniker "Your Validator Name" \
  --identity "" \
  --website "" \
  --security-contact "" \
  --details "Your validator description" \
  --chain-id medasdigital-2 \
  --commission-rate 0.05 \
  --commission-max-rate 0.20 \
  --commission-max-change-rate 0.01 \
  --min-self-delegation 1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --fees 5000umedas \
  --from wallet-name

# Check validator status
medasdigitald query staking validator $(medasdigitald keys show wallet-name --bech val -a)
```

## Node Management Commands

### Service Management

```bash
# Start the service
sudo systemctl start medasdigital

# Stop the service
sudo systemctl stop medasdigital

# Restart the service
sudo systemctl restart medasdigital

# Check service status
sudo systemctl status medasdigital

# Enable service to start on boot
sudo systemctl enable medasdigital

# Disable service from starting on boot
sudo systemctl disable medasdigital
```

### Monitoring and Troubleshooting

```bash
# View real-time logs
journalctl -u medasdigital -f

# View recent logs
journalctl -u medasdigital --since "1 hour ago"

# Check node status
medasdigitald status

# Check sync status
medasdigitald status | jq .SyncInfo

# Check connected peers
medasdigitald query tendermint-validator-set

# Check validator info
medasdigitald query staking validators --limit 100
```

### Wallet Operations

```bash
# Send tokens
medasdigitald tx bank send wallet-name <recipient-address> 1000000umedas --fees 5000umedas

# Check balance
medasdigitald query bank balances $(medasdigitald keys show wallet-name -a)

# Delegate to validator
medasdigitald tx staking delegate <validator-address> 1000000umedas --from wallet-name --fees 5000umedas

# Withdraw rewards
medasdigitald tx distribution withdraw-all-rewards --from wallet-name --fees 5000umedas
```

## Security Best Practices

When running a validator node, consider these security measures:

1. **Firewall Configuration**: Only open necessary ports (26656 for P2P, 26657 for RPC if needed)
1. **Key Management**: Store your validator keys securely and consider using a hardware security module
1. **Monitoring**: Set up monitoring and alerting for your validator
1. **Backup**: Regularly backup your validator keys and node data
1. **Updates**: Keep your node software updated to the latest version

## Troubleshooting

### Common Issues

**Node won’t start**: Check logs with `journalctl -u medasdigital -f` for specific error messages

**Sync issues**: Verify peers are configured correctly and genesis file is valid

**Out of disk space**: Monitor disk usage and clean up old logs if necessary

**Memory issues**: Ensure your system has sufficient RAM and consider enabling swap

### Getting Help

If you encounter issues not covered in this guide:

1. Check the logs for specific error messages
1. Consult the community forums or Discord
1. Review the GitHub repository for known issues
1. Contact the development team for technical support

## Building MedasDigital 2.0 Together

By following this comprehensive setup guide, you’ll be contributing to the MedasDigital 2.0 network as either a node operator or validator. Your participation helps strengthen the network’s security and decentralization.

Stay tuned for updates and improvements to the network. We look forward to building the future of MedasDigital 2.0 together!

## License

This project is licensed under the MIT License. Please see the LICENSE file for more details.
