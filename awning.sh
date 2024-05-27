#!/bin/bash

# Function to generate a random password
generate_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo ''
}

# Function to get the latest versions of software excluding 'rc' tags from GitHub
get_latest_versions() {
    local repo=$1
    curl -s "https://api.github.com/repos/${repo}/tags" | grep -oP '"name": "\K(.*?)(?=")' | grep -v 'rc' | head -n 5
}

# Function to detect architecture
detect_architecture() {
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        echo "x86_64 amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        echo "aarch64 arm64"
    else
        echo "Unsupported architecture: $arch" >&2
        exit 1
    fi
}

# Function to create .env file
create_env_file() {
    local myuid=$1
    local mygid=$2
    local bitcoin_arch=$3
    local lnd_arch=$4
    local bitcoin_versions=("${!5}")
    local lnd_versions=("${!6}")
    local electrs_versions=("${!7}")

    echo -n "Enter value for RTL_PASSWORD: "
    read rtl_password

    cat <<EOT > .env
UID=${myuid}
GID=${mygid}
BITCOIN_ARCH=${bitcoin_arch}
LND_ARCH=${lnd_arch}
LND_PASSWORD=$(generate_password)
BITCOIN_CORE_VERSION=${bitcoin_versions[0]}
LND_VERSION=${lnd_versions[0]}
ELECTRS_VERSION=${electrs_versions[0]}
RTL_PASSWORD=${rtl_password}
EOT
    echo ".env file created with default values."
}

# Function to update UID and GID in .env file
update_env_file() {
    local myuid=$1
    local mygid=$2
    sed -i "s/^UID=.*/UID=${myuid}/" .env
    sed -i "s/^GID=.*/GID=${mygid}/" .env
}

# Function to display menu
display_menu() {
    local bitcoin_versions=("${!1}")
    local lnd_versions=("${!2}")
    local electrs_versions=("${!3}")

    while true; do
        echo ""
        echo "Menu:"
        echo "1) Start the node"
        echo "2) Change RTL_PASSWORD"
        echo "3) Change BITCOIN_CORE_VERSION"
        echo "4) Change LND_VERSION"
        echo "5) Change ELECTRS_VERSION"
        echo "6) Exit"
        echo -n "Choose an option: "
        read option

        case $option in
            1)
                echo "Starting the node..."
                # Add node start logic here
                ;;
            2)
                change_rtl_password
                ;;
            3)
                change_version "BITCOIN_CORE_VERSION" bitcoin_versions[@]
                ;;
            4)
                change_version "LND_VERSION" lnd_versions[@]
                ;;
            5)
                change_version "ELECTRS_VERSION" electrs_versions[@]
                ;;
            6)
                echo "Exiting."
                break
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}

# Function to change RTL_PASSWORD
change_rtl_password() {
    echo -n "Enter new RTL_PASSWORD (press ENTER to keep current): "
    read new_rtl_password
    if [ ! -z "$new_rtl_password" ]; then
        sed -i "s/^RTL_PASSWORD=.*/RTL_PASSWORD=${new_rtl_password}/" .env
        echo "RTL_PASSWORD updated."
    else
        echo "RTL_PASSWORD unchanged."
    fi
}

# Function to change version
change_version() {
    local version_name=$1
    local versions=("${!2}")

    echo "Select $version_name:"
    for i in "${!versions[@]}"; do
        echo "$((i+1))) ${versions[$i]}"
    done
    echo -n "Choose a version (press ENTER to keep current): "
    read version_index
    if [ ! -z "$version_index" ] && [ "$version_index" -le "${#versions[@]}" ]; then
        sed -i "s/^${version_name}=.*/${version_name}=${versions[$((version_index-1))]}/" .env
        echo "$version_name updated."
    else
        echo "$version_name unchanged."
    fi
}

# Main script logic
MYUID=$(id -u)
MYGID=$(id -g)
ARCH_INFO=($(detect_architecture))
BITCOIN_ARCH=${ARCH_INFO[0]}
LND_ARCH=${ARCH_INFO[1]}
BITCOIN_VERSIONS=($(get_latest_versions "bitcoin/bitcoin"))
LND_VERSIONS=($(get_latest_versions "lightningnetwork/lnd"))
ELECTRS_VERSIONS=($(get_latest_versions "romanz/electrs"))

if [ ! -f .env ]; then
    create_env_file "$MYUID" "$MYGID" "$BITCOIN_ARCH" "$LND_ARCH" BITCOIN_VERSIONS[@] LND_VERSIONS[@] ELECTRS_VERSIONS[@]
else
    update_env_file "$MYUID" "$MYGID"
    display_menu BITCOIN_VERSIONS[@] LND_VERSIONS[@] ELECTRS_VERSIONS[@]
fi
