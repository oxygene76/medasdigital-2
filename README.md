# Welcome to MedasDigital 2.0: Building the Future of Decentralized Finance and Digital Ownership

MedasDigital 2.0 is an innovative blockchain project built on the Cosmos SDK, designed to empower users with a decentralized platform for finance, asset creation, and ownership. With a focus on security, flexibility, and ease of use, MedasDigital 2.0 is set to redefine how individuals and businesses engage with blockchain technology.

## Key Features of MedasDigital 2.0

- **Token Creation and Management**: MedasDigital 2.0 allows users to easily create, issue, and manage custom tokens. Whether for personal, business, or community purposes, our platform offers a streamlined experience for tokenization.
  
- **NFT Functionality**: Supporting the full life cycle of Non-Fungible Tokens (NFTs), MedasDigital 2.0 enables users to create, trade, and manage digital assets. From art to collectibles, MedasDigital 2.0 provides a secure and scalable environment for digital ownership.

- **Smart Contracts and WASM Support**: Our WASM integration supports smart contracts, enabling advanced functionalities for decentralized applications (dApps) and allowing developers to bring their unique ideas to life on a robust, secure blockchain.

- **Enhanced Security and Decentralization**: Built with the Cosmos SDK, MedasDigital 2.0 leverages Tendermint’s consensus engine, offering a high-performance, secure network. The platform’s design encourages decentralization, creating a resilient ecosystem supported by a global community of validators and node operators.

- **Community-Focused Governance**: MedasDigital 2.0 empowers its community with governance features, allowing token holders to influence network upgrades and policies directly. Through transparent and decentralized decision-making, MedasDigital 2.0 ensures that the community remains at the heart of the project’s evolution.

## A Growing Ecosystem with Real-World Use Cases

MedasDigital 2.0 is more than a blockchain; it's a thriving ecosystem designed to bring real-world applications to decentralized finance (DeFi), digital ownership, and beyond. With support for token creation, NFTs, and smart contracts, MedasDigital 2.0 provides an ideal environment for developers, entrepreneurs, and community members to innovate and grow.

Join us as we build the future of blockchain technology. MedasDigital 2.0 is committed to creating a decentralized, user-centric platform that unlocks new possibilities in digital ownership and finance. Whether you’re a developer, validator, or simply a blockchain enthusiast, there’s a place for you in the MedasDigital 2.0 ecosystem.

---

## MedasDigital 2.0 Launch: A Phased Validator and Node Approach

To ensure a stable and seamless start, we’re launching MedasDigital 2.0 with a set of our own initial validators. This approach allows us to closely monitor network stability, optimize performance, and ensure a secure environment for all participants.

### Why Start with Our Own Validators?

- **Stability and Reliability**: By beginning with our own validators, we maintain complete control over network stability during the critical early phase, minimizing potential issues.
- **Security Optimization**: Launching with our validators allows us to monitor security metrics closely and make any necessary adjustments before opening the network to external participants.
- **Gradual Decentralization**: Shortly after launch, we’ll expand validator and node access, enabling community members to join and contribute to network growth.

---

## Join MedasDigital 2.0 as a Validator or Node

Very soon after the initial launch, everyone interested in supporting MedasDigital 2.0 can set up their own **validator** or **node** with our **Automated Setup Script**. This script simplifies the process, allowing participants to join as a validator for full participation in network security or as a node operator if they prefer not to validate actively.

### Quick Start: Node Setup with `medasdigital_setup.sh`

The `medasdigital_setup.sh` script automates the process of setting up a Medas Digital 2.0 node, creating wallets, and configuring validators.

#### Step 1: Download the Setup Script

To download the setup script under Linux, use the following command:

```bash
wget https://raw.githubusercontent.com/oxygene76/medasdigital-2/refs/heads/main/medasdigital_setup.sh
```

#### Step 2: Make the Script Executable and Run It

Make sure you have the necessary permissions, then make the script executable and run it with:

```bash
chmod +x medasdigital_setup.sh
./medasdigital_setup.sh
```

### Script Options

The setup script will provide the following options:

1. **Setup Node** - Installs the latest `medasdigitald` binary, sets up configuration files, and synchronizes the node with the network.
2. **Setup Validator** - Guides you through creating a validator, including setting commission rates and moniker.
3. **Create Wallet** - Creates a new wallet address for the chain.
4. **Import Wallet** - Allows you to import an existing wallet using either a mnemonic phrase or private key.
5. **List Wallets** - Displays a list of all wallets created on this node.
6. **Create Systemd Service** - Sets up the node as a systemd service to ensure it runs in the background and restarts on reboot.
7. **View Node Logs** - Displays the real-time logs of the MedasDigital node to monitor its activity and troubleshoot issues.
8. **View Node Status** - Shows detailed information about the node status, including synchronization status, current block height, connected peers, and the validator who signed the latest block.

## Example: Setting up a Validator

After setting up the node, you can create a validator by selecting Option 2. You’ll be prompted to enter:

- Wallet name
- Amount to stake
- Commission rate details
- Validator moniker (name)

This process will register your validator on the Medas Digital 2.0 network.

## Starting and Checking the MedasDigital Node Service

If you’ve used the setup script to create a systemd service, you can start, stop, and check the status of your MedasDigital node using `systemctl`.

### Step 1: Start the MedasDigital Service

To start the node service, use the following command:

```bash
sudo systemctl start medasdigital
```

### Step 2: Enable the Service to Start on Boot

To ensure your node service starts automatically when the server reboots, enable the service:

```bash
sudo systemctl enable medasdigital
```

### Step 3: Check if the Service is Running

To verify that your node service is active and running, check its status:

```bash
sudo systemctl status medasdigital
```

You should see an output indicating that the service is "active (running)". If there are any issues, the status command will also show error messages to help diagnose them.

### Step 4: Monitor Node Logs

For a more detailed look at what your node is doing, you can view the service logs with:

```bash
journalctl -fu medasdigital
```

This command displays real-time logs from the MedasDigital node, which can be useful for troubleshooting and ensuring the node is syncing properly with the network.

## Building MedasDigital 2.0 Together

By starting with a phased approach, MedasDigital 2.0 aims to build a stable, secure, and progressively decentralized network from the beginning. Stay tuned for updates on how to set up your own validator or node with our easy-to-use setup tools. We look forward to building the future of MedasDigital 2.0 together!

## License

This project is licensed under the [LICENSE NAME]. Please see the LICENSE file for more details.
