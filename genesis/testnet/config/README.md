### Step-by-Step Guide to Building the MedasDigital Binary

This guide describes how to build the **MedasDigital** binary from source.

#### 1. Install Dependencies
1.1. Update the local package list and install required packages:
```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install make build-essential gcc git jq chrony -y
```

1.2. Install Go (version 1.22 or higher):
```bash
wget https://go.dev/dl/go1.22.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.22.linux-amd64.tar.gz
```

1.3. Configure environment variables:
```bash
cat <<EOF >> ~/.profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF

source ~/.profile
```
- Verify the Go installation:
```bash
go version
```
- The output should be `go version go1.22 linux/amd64`.

#### 2. Clone the MedasDigital Repository
2.1. Clone the MedasDigital repository from GitHub:
```bash
git clone https://github.com/<your-repo>/medasdigital.git
cd medasdigital
```

#### 3. Build the Binary
3.1. Use `make` to build the binary:
```bash
make install
```
- This will install the `medasdigitald` binary in your `$GOPATH/bin` directory.

3.2. Verify the installation by checking the version:
```bash
medasdigitald version
```

### Step-by-Step Guide to Setting Up Validators for the MedasDigital Testnet

This guide describes the steps to correctly set up **validators** for the MedasDigital chain testnet and integrate `gentx` transactions into the genesis file.

#### 1. Creating Validator Key Pairs
1.1. On each node that will be a validator, create a key pair:
```bash
medasdigitald keys add <validator-name> --keyring-backend test
```
- **`<validator-name>`**: Choose a name for the validator.

1.2. Note down the generated **address** for the validator key.

#### 2. Creating `gentx` Transactions
2.1. Create a **`gentx` transaction** for each validator:
```bash
medasdigitald gentx <validator-name> 1000000000umedastest --chain-id medasdigital-test-2 --moniker "<validator-moniker>"
```
- **`<validator-name>`**: The name of the validator used in the previous step.
- **`<validator-moniker>`**: Publicly visible name of the validator.

2.2. The `gentx` file will be created in the directory **`~/.medasdigitald/config/gentx/`**.

#### 3. Collecting `gentx` Transactions
3.1. Collect all **`gentx` files** from all nodes and copy them into the **`gentxs` folder** of the genesis file:
```bash
cp ~/.medasdigitald/config/gentx/*.json ~/.medasdigitald/config/gentxs/
```

#### 4. Integrating `gentx` Transactions into the Genesis File
4.1. Add all `gentx` transactions to the genesis file:
```bash
medasdigitald collect-gentxs
```
- This command integrates the `gentx` transactions and updates the **genesis file** accordingly.

#### 5. Validating the Genesis File
5.1. Validate the updated genesis file:
```bash
medasdigitald validate-genesis
```
- This step ensures that the genesis file is error-free.

#### 6. Starting the Testnet
6.1. Once the genesis file has been successfully validated, start the testnet:
```bash
medasdigitald start
```



