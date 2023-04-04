#!/bin/bash

# Set wallet address, private key, record and log file path
# Parse command-line arguments
if [[ $# -eq 3 ]]; then
    PRIVATE_KEY="$1"
    WALLET_ADDRESS="$2"
    RECORD="$3"
else
    # Prompt the user to enter missing arguments
    read -p "Enter private key: " PRIVATE_KEY
    read -p "Enter wallet address: " WALLET_ADDRESS
    read -p "Enter record: " RECORD
fi
LOGFILE="snarkos_install_log.txt"

# Check if log file exists
if [ ! -f "$LOGFILE" ]; then
    # Create log file if it doesn't exist
    touch "$LOGFILE"
fi

# Function to retry commands
step=1
retry() {
    local n=1
    local max_attempts=3
    while true; do
        "$@" >> $LOGFILE 2>&1 && break || {
            if [[ $n -lt $max_attempts ]]; then
                n=$((n+1))
                echo "Command failed. Retrying in 5 seconds (attempt $n of $max_attempts)..." >> $LOGFILE
                sleep 5s
            else
                echo "Command failed after $max_attempts attempts. Exiting in step $step." >> $LOGFILE
                exit 1
            fi
        }
    done
    step=$((step+1))
}

# Update package manager and install required packages
retry sudo apt-get update # step 1
retry sudo apt-get -y upgrade # step 2
retry sudo apt-get -y install screen curl git # step 3

# Download and install Rust
retry curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh # step 4

# Clone the repository and build snarkOS
retry git clone https://github.com/AleoHQ/snarkOS.git --depth 1 # step 5
cd snarkOS && retry ./build_ubuntu.sh
retry source $HOME/.cargo/env && retry cargo install --path . # step 6

# Clone and install Leo
cd ~
retry git clone https://github.com/AleoHQ/leo # step 7
cd leo
retry cargo install --path . # step 8
echo "Leo installed."

# Set app name based on wallet address
APPNAME="helloworld_${WALLETADDRESS:4:6}"
echo "App name: $APPNAME"

# Create and deploy test app
cd ~
mkdir demo_deploy_Leo_app && cd demo_deploy_Leo_app
retry leo new "${APPNAME}" # step 1 9
cd "${APPNAME}" && leo run && cd -
PATHTOAPP=$(realpath -q $APPNAME)
echo "Path to app: $PATHTOAPP"
cd $PATHTOAPP && cd ..

# Deploy app with retries
TRIES=3
for (( i=1; i<=$TRIES; i++ ))
do
    echo "Deploying app (attempt $i/$TRIES)..."
    retry snarkos developer deploy "${APPNAME}.aleo" --private-key "${PRIVATEKEY}" --query "https://vm.aleo.org/api" --path "./${APPNAME}/build/" --broadcast "https://vm.aleo.org/api/testnet3/transaction/broadcast" --fee 600000 --record "${RECORD}" # step 10
    if [ $? -eq 0 ]; then
        echo "App deployed successfully."
        break
    else
        echo "Deployment failed."
        if [ $i -eq $TRIES ]; then
            echo "Maximum number of retries reached."
            exit 1
        else
            echo "Retrying in 10 seconds..."
            sleep 10
        fi
    fi
done
