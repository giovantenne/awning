#!/bin/bash

RED='\033[0;31m'
ORANGE='\033[38;5;214m'
LIGHT_BLUE='\033[1;34m'
UNDERLINE='\033[4m'
GREEN='\033[0;32m'
MAGENTA="\e[36m"
NC='\033[0m' # No Color
BOLD='\e[1m'
NB='\e[0m'

# Function to get the latest versions of software excluding 'rc' tags from GitHub
get_latest_versions() {
  local repo=$1
  curl -s "https://api.github.com/repos/${repo}/tags" | grep -oP '"name": "\K(.*?)(?=")' | grep -v 'rc' | sed 's/\(beta\).*/\1/' | head -n 5
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

MYUID=$(id -u)
MYGID=$(id -g)
ARCH_INFO=($(detect_architecture))
BITCOIN_ARCH=${ARCH_INFO[0]}
LND_ARCH=${ARCH_INFO[1]}

# Print header
print_header() {
  echo "-----------"
  echo -e "${BOLD}${ORANGE}$1) $2${NC}${NB} "
  # echo -e "${BOLD}$2${NB}"
  echo "-----------"
  # sleep 1
}

# Function to check if Bitcoin blockchain is downloaded
is_bitcoin_blockchain_downloaded() {
  local blocks_folder="./data/bitcoin/blocks"
  if [ -d "$blocks_folder" ] && [ "$(ls -A $blocks_folder)" ]; then
    return 0
  else
    return 1
  fi
}

# Function to check if LND is initialized
is_lnd_initialized() {
  channel_backup_file="./data/lnd/data/chain/bitcoin/mainnet/channel.backup"
  if [ -f "$channel_backup_file" ]; then
    return 0
  else
    return 1
  fi
}

# Function to generate a random password
generate_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo ''
}

# Function to check if input is a valid SSH GitHub repository URL
is_ssh_github_repo() {
  local input="$1"
  local regex='^git@github\.com:[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.git$'

  if [[ $input =~ $regex ]]; then
    return 0
  else
    return 1
  fi
}

is_disk_space_available() {
  script_dir="$(dirname "$(readlink -f "$0")")"
  partition=$(df -P "$script_dir" | tail -1 | awk '{print $6}')
  free_space_kb=$(df -P "$partition" | tail -1 | awk '{print $4}')
  data_dir="$script_dir/data"
  data_size_kb=$(du -sk "$data_dir" | awk '{print $1}')
  required_free_space_kb=$((900000000 - data_size_kb))
  if (( free_space_kb >= required_free_space_kb )); then
    return 0
  else
    return 1
  fi
}

show_welcome() {
  echo -e ""
  echo -e "Welcome to the ${ORANGE}${BOLD}Awning${NB}${NC} setup tutorial!"
  echo -e "This script will guide you through setting up a full dockerized Bitcoin/LND/BTCPay server on your PC."
  echo -e ""
  echo -e "${BOLD}************ DISCLAIMER ****************${NB}"
  echo -e "${BOLD}This open-source project ('the Project') is provided 'as-is' without any warranty of any kind, either expressed or implied. The developers are not liable for any damages or losses arising out of the use of this software.${NB}"
  echo -e "${BOLD}Please read the full disclaimer before using the Project here: ${UNDERLINE}https://github.com/giovantenne/awning/blob/master/DISCLAIMER.md${NC}${NB}"
  echo -e "${BOLD}By using the Project, you acknowledge that you have read, understood, and agree to be bound by this disclaimer. If you do not agree to this disclaimer, you should not use the Project.${NB}"
  echo -e "${BOLD}****************************************${NB}"
  echo -e ""
  if ! is_disk_space_available; then
    echo -e "${RED}The disk where you are running Awning doesn't have enough free space and can not contain the Bitcoin blockchain.${NC}"
    echo -e "${RED}Please exit this setup with CTRL+C use a different disk.${NC}"
    echo -e "----------------"
  fi
  if ! is_bitcoin_blockchain_downloaded; then
    echo -e "It seems that you need to download the entire ${ORANGE}Bitcoin${NC} blockchain. This will take some time..."
    echo -e "If you already have the blockchain downloaded somewhere, please move it to ${UNDERLINE}./data/bitcoin/${NC} now."
    echo -e "----------------"
  fi
  if ! is_lnd_initialized; then
    touch ./data/lnd/password.txt
    echo -e "It seems that you need to initialize your ${LIGHT_BLUE}LND${NC} wallet."
    echo -e "If you already have your LND data somewhere, please move it to ${UNDERLINE}./data/lnd/${NC} now."
    echo -e "----------------"
  fi

  echo -e ""
  echo "Press any key to continue..."
  read -n 1 -s -r
}

choose_alias() {
  print_header $1 "LND node alias"
  echo -e "Choose the alias your LND node will use, which can be up to 32 UTF-8 characters in length."
  echo -e ""
  echo -n "Insert alias (default is 'AwningNode'): "
  read NODE_ALIAS
  NODE_ALIAS=${NODE_ALIAS:-AwningNode}
}

insert_scb_repo() {
  print_header $1 "LND channel backups"
  echo -e "The Static Channels Backup (SCB) is a feature of ${LIGHT_BLUE}LND${NC} that allows for the on-chain recovery of lightning channel balances in the case of a bricked node. Despite its name, it does not allow the recovery of your LN channels but increases the chance that you'll recover all (or most) of your off-chain (local) balances."
  echo -e ""
  echo -e "${BOLD}Awning${NB} will automatically upload a copy of your ${UNDERLINE}channel.backup${NC} every time it changes on a Github repository you own, so you will need to create one and provide upload credential later."
  echo -e ""
  echo -e "${BOLD}Create a GitHub repository${NB}"
  echo -e "   - Go to GitHub (${UNDERLINE}https://github.com${NC}), sign up for a new user account, or log in with an existing one."
  echo -e "   - Create a new repository: ${UNDERLINE}https://github.com/new${NC}"
  echo -e "       - Choose a repository name (eg. ${BOLD}remote-lnd-backup${NB})"
  echo -e "       - Select 'Private' (rather than the default 'Public')"
  echo -e "       - Click on 'Create repository'"
  echo -e "       - Annotate your SSH repository address."
  echo -e "         It should be something like ${UNDERLINE}git@github.com:giovantenne/remote-lnd-backup.git${NC}"

  echo -e ""
  if [ -f .env ]; then
    current_repo=$(grep -E '^\s*SCB_REPO\s*=' .env | sed -e 's/^\s*SCB_REPO\s*=\s*//' -e 's/\s*$//')
  else
    current_repo=""
  fi
  while true; do
    if [ -z "$current_repo" ]; then
      echo -en "Enter your SSH repository address: "
    else
      echo -e "Current value: ${UNDERLINE}$current_repo${NC}"
      echo -en "Enter your SSH repository address (press ENTER to keep current): "
    fi
    read SCB_REPO
    if [ -z "$SCB_REPO" ]; then
      SCB_REPO=$current_repo
    fi
    if is_ssh_github_repo "$SCB_REPO"; then
      break
    else
      echo -e "${RED}${BOLD}Invalid address${NB}${NC}"
    fi
  done
}

upload_scb_repo_deploy_key() {
  print_header $1 "Authorize SCB to be uploaded on Github"
  if [ ! -f ./data/scb/.ssh/id_rsa.pub ]; then
    echo -e "Generating the SSH key. This could take a few minutes. Please wait..."
    mkdir -p ./data/scb/.ssh

    # Generating ssh key
    $docker_command run --rm -e MYUID=$MYUID -e MYGID=$MYGID -v "$PWD/data/scb/.ssh:/keys" debian:bookworm-slim sh -c "
    apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client && \
      ssh-keygen -t rsa -b 2048 -f /keys/id_rsa -N '' && \
      chown $MYUID:$MYGID /keys/*" >/dev/null 2>&1

    # adding github public key fingerprints
  else
    echo -e "SSH key already present in ${UNDERLINE}./data/scb/.ssh/${NC}"
  fi
  if [ ! -f ./data/scb/.ssh/known_hosts ]; then
    echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
    github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> ./data/scb/.ssh/known_hosts
  fi

  echo -e "************************${GREEN}"
  cat ./data/scb/.ssh/id_rsa.pub
  echo -e "${NC}************************"
  # Extract the username and repository name using parameter expansion
  # The SSH URL is expected to be in the format: git@github.com:username/repository.git
  local username=$(echo $SCB_REPO | cut -d':' -f2 | cut -d'/' -f1)
  local repository=$(echo $SCB_REPO | cut -d'/' -f2 | sed 's/\.git$//')
  echo -e ""
  echo -e "- Go to the following address: ${UNDERLINE}https://github.com/$username/$repository/settings/keys/new${NC}"
  echo -e "- Type a title (e.g., 'SCB')"
  echo -e "- In the 'Key' box, copy/paste the SSH key generated above (e.g. ${UNDERLINE}ssh-rsa 56fgh... scb@5cf1058457${NC})"
  echo -e "- Tick the box 'Allow write access' to enable this key to push changes to the repository"
  echo -e "- Click 'Add key'"
  echo -e ""
  echo -e "Press ENTER to test your setup"
  read -n 1 -s -r
  rm -rf ./data/scb/test
  cd ./data/scb
  while true; do
    echo -e "Performing test. Please wait..."
    # Test read
    if ! git config --global user.email &>/dev/null; then
      git config --global user.email "awning@example.com"
    fi
    if ! git config --global user.name &>/dev/null; then
      git config --global user.name "Awning"
    fi
    GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=.ssh/known_hosts -o IdentitiesOnly=yes -i .ssh/id_rsa" git clone $SCB_REPO test
    if [ $? -ne 0 ]; then
      echo -e "${RED}${BOLD}Read rest failed!${NB}${NC}"
      echo -e "You do not have permission to read to ${UNDERLINE}$SCB_REPO${NC}"
      echo -e "Please follow the above steps again and press ENTER to try again or CRTL-C to exit the setup."
      read -n 1 -s -r
    else
      cd test
      touch test >/dev/null 2>&1
      git add test   >/dev/null 2>&1
      git commit -am "Test"  >/dev/null 2>&1
      git branch -M main
      # Test write
      GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=../.ssh/known_hosts -o IdentitiesOnly=yes -i ../.ssh/id_rsa" git push $SCB_REPO main #>/dev/null 2>&1
      if [ $? -ne 0 ]; then
        cd ..
        rm -rf test
        echo -e "${RED}${BOLD}Write test failed!${NB}${NC}"
        echo -e "You do not have permission to write to ${UNDERLINE}$SCB_REPO${NC}"
        echo -e "Please follow the above steps again and press ENTER to try again or CRTL-C to exit the setup."
        read -n 1 -s -r
      else
        # Cleanup
        rm test
        git commit -am "Test successful"  >/dev/null 2>&1
        GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=../.ssh/known_hosts -o IdentitiesOnly=yes -i ../.ssh/id_rsa" git push $SCB_REPO main #>/dev/null 2>&1
        cd ../../../
        rm -rf ./data/scb/test
        echo -e ""
        echo -e "${GREEN}${BOLD}Test performed successfully${NB}${NC}"
        echo "Press any key to continue..."
        read -n 1 -s -r
        break
      fi
    fi
  done
}

choose_rtl_password() {
  print_header $1 "${BOLD}'Ride The Lightning' password${NB}"
  read -s -p "Please choose your password for the RTL web interface: " RTL_PASSWORD
  echo -e ""
}

enable_btcpay() {
  print_header $1 "${BOLD}BTCPay server${NB}"
  while true; do
    echo -n "Do you want to run BTCPay-server? (yes/no, default is no): "
    read RUN_BTCPAY
    RUN_BTCPAY=${RUN_BTCPAY:-no}
    if [[ "$RUN_BTCPAY" =~ ^(yes|no)$ ]]; then
      break
    else
      echo "Invalid choice. Please enter 'yes' or 'no'."
    fi
  done
}

function check_lnd(){
  while [ "$($docker_command inspect -f '{{.State.Running}}' awning_lnd 2>/dev/null)" != "true" ]; do
    echo -e "Waiting for LND container to start..."
    sleep 10
    echo "Timed out waiting for the container to start."
  done

  if is_lnd_initialized; then
    if [ ! -s "./data/lnd/password.txt" ]; then
      print_header $1 "${BOLD}Insert your LND wallet password${NB}"
      echo -e "Please insert your password for automatically unlock your LND wallet. If you come from Umbrel please insert 'moneyprintergobrrr'"
      read -s -p "Please insert your password: " LND_PASSWORD
      echo -e ""
      echo $LND_PASSWORD > ./data/lnd/password.txt
      $compose_command restart lnd
    fi
  else
    # Wait for the container to be running
    local timeout=60
    local wait_interval=2
    elapsed=0
    print_header $1 "${BOLD}Create your LND wallet password${NB}"
    echo -e "Please choose your password for automatically unlock your LND wallet."
    echo -e "You will need to re-enter the password 3 times on the next step."
    echo -e ""
    while true; do
      read -s -p "Enter your wallet password (first time of three): " password
      echo -e ""
      if [ ! ${#password} -ge 8 ]; then
        echo "password must have at least 8 characters"
        echo -e ""
      else
        break
      fi
    done
    echo $password > ./data/lnd/password.txt
    $docker_command exec -it awning_lnd lncli create
    echo -e ""
  fi
}

function create_env_file() {
  BITCOIN_VERSIONS=($(get_latest_versions "bitcoin/bitcoin"))
  LND_VERSIONS=($(get_latest_versions "lightningnetwork/lnd"))
  ELECTRS_VERSIONS=($(get_latest_versions "romanz/electrs"))
  cat <<EOT > .env
UID=${MYUID}
GID=${MYGID}
NODE_ALIAS=${NODE_ALIAS}
BITCOIN_ARCH=${BITCOIN_ARCH}
LND_ARCH=${LND_ARCH}
RTL_PASSWORD=${RTL_PASSWORD}
SCB_REPO=${SCB_REPO}
BITCOIN_CORE_VERSION=$(echo ${BITCOIN_VERSIONS[0]} | sed 's/^v//')
LND_VERSION=$(echo ${LND_VERSIONS[0]} | sed 's/^v//')
ELECTRS_VERSION=$(echo ${ELECTRS_VERSIONS[0]} | sed 's/^v//')
EOT
}

function create_compose() {
  cat <<EOT > docker-compose.yml
version: "3"
services:
EOT
cat ./fragments/tor.yml >> docker-compose.yml
cat ./fragments/bitcoin.yml >> docker-compose.yml
cat ./fragments/electrs.yml >> docker-compose.yml
cat ./fragments/lnd.yml >> docker-compose.yml
cat ./fragments/scb.yml >> docker-compose.yml
cat ./fragments/rtl.yml >> docker-compose.yml
cat ./fragments/nginx.yml >> docker-compose.yml
if [ "$RUN_BTCPAY" = "yes" ]; then
  sed -i '/^  nginx:/,/depends_on:/s/^ *depends_on: \[rtl, electrs\]/    depends_on: [rtl, electrs, btcpay]/' docker-compose.yml
  sed -i '/nginx:/,/restart: unless-stopped/{s/^      #\s*/      /}' docker-compose.yml
  sed -i 's/nginx-reverse-proxy/nginx-reverse-proxy-btcpay/g' docker-compose.yml
  cat ./fragments/btcpay.yml >> docker-compose.yml
fi

}

compose_build() {
  print_header $1 "You are now ready to build your Docker images"
  echo -e "The first time it will take some time to build all the images from scratch (especially compiling the Electrs binary can take up to one hour)."
  echo -e ""
  echo "Press any key to continue..."
  read -n 1 -s -r
  $compose_command build
  echo -e "${GREEN}${BOLD}Build completed${NB}${NC}"
  echo "Press any key to continue..."
  read -n 1 -s -r
}

are_services_up() {
  $compose_command ps | grep ' Up ' > /dev/null
  echo $?

}


# Function to display menu
display_menu() {
  while true; do
    echo ""
    echo "#############################################"
    echo -e "#                  ${BOLD}${ORANGE}Awning${NC}${NB}                   #"
    echo "#############################################"
    echo "1) Start/Stop the node"
    echo "2) Logs"
    echo "3) Node info"
    echo "4) Change node parameters"
    echo "5) Connections URLs"
    echo "6) Utilities"
    echo -e "${BOLD}0) Exit${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option

    case $option in
      1)
        echo "Loading..."
        echo ""
        if [ $(are_services_up) -ne 0 ]; then
          read -p "Node is not running. Do you want to start the node? (y/n): " answer
          if [[ $answer =~ ^[Yy]$ ]]; then
            echo "Starting the node..."
            $compose_command up -d
          fi
        else
          read -p "Node is running. Do you want to stop the node? (y/n): " answer
          if [[ $answer =~ ^[Yy]$ ]]; then
            echo "Stopping the node..."
            $compose_command down
          fi
        fi
        ;;
      2)
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          logs_submenu
        fi
        ;;
      3)
        echo "Loading..."
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          show_node_info
        fi
        ;;
      4)
        node_params_submenu
        ;;
      5)
        connections_submenu
        ;;
      6)
        utils_submenu
        ;;
      0)
        echo "Exiting."
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

show_node_info() {
    bitcoin_version=$($docker_command exec awning_bitcoin bitcoin-cli --version | grep "Bitcoin Core RPC client version")
    sync_percentage=$($docker_command exec awning_bitcoin /bin/bash -c 'echo "`bitcoin-cli getblockchaininfo | jq -r '.verificationprogress'` * 100" | bc')
    blocks=$($docker_command exec awning_bitcoin /bin/bash -c "bitcoin-cli getblockchaininfo | jq -r '.blocks'")
    headers=$($docker_command exec awning_bitcoin /bin/bash -c "bitcoin-cli getblockchaininfo | jq -r '.headers'")
    initialblockdownload=$($docker_command exec awning_bitcoin /bin/bash -c "bitcoin-cli getblockchaininfo | jq -r '.initialblockdownload'")

    lnd_version=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.version'")
    synced_to_chain=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.synced_to_chain'")
    synced_to_graph=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.synced_to_graph'")
    num_pending_channels=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.num_pending_channels'")
    num_active_channels=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.num_active_channels'")
    num_inactive_channels=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.num_inactive_channels'")
    num_peers=$($docker_command exec awning_lnd /bin/bash -c "lncli getinfo | jq -r '.num_peers'")
    echo ""
    echo -e "${ORANGE}BITCOIN${NC}"
    echo -e $bitcoin_version
    echo -e "Sync Progress: $sync_percentage%"
    echo -e "Blocks: $blocks"
    echo -e "Headers: $headers"
    echo -e "Initial block download: $initialblockdownload"
    echo ""
    echo -e "${LIGHT_BLUE}LND${NC}"
    echo -e "Version $lnd_version"
    echo -e "Synced to Chain: $synced_to_chain"
    echo -e "Synced to Graph: $synced_to_graph"
    echo -e "Num. active channels: $num_active_channels"
    echo -e "Num. pending channels: $num_pending_channels"
    echo -e "Num. inactive channels: $num_inactive_channels"
    echo -e "Num. peers: $num_peers"
    echo ""
    echo "Press any key to continue..."
    read -n 1 -s -r
}

logs_submenu(){
  while true; do
    echo "#############################################"
    echo -e "#           Logs (CRTL+C to exit)           #"
    echo "#############################################"
    echo "1) All the logs"
    echo "2) Bitcoin logs"
    echo "3) LND logs"
    echo "4) Electrs logs"
    echo "5) RTL logs"
    echo "6) TOR logs"
    echo "7) SCB logs"
    echo ""
    echo -e "${BOLD}0) <- Back to main menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        $compose_command logs --tail 100 -f 
        ;;
      2)
        $compose_command logs --tail 100 -f bitcoin
        ;;
      3)
        $compose_command logs --tail 100 -f lnd
        ;;
      4)
        $compose_command logs --tail 100 -f electrs
        ;;
      5)
        $compose_command logs --tail 100 -f rtl
        ;;
      6)
        $compose_command logs --tail 100 -f tor
        ;;
      7)
        $compose_command logs --tail 100 -f scb
        ;;
      0)
        display_menu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

node_params_submenu() {
  while true; do
    echo "#############################################"
    echo "#            Change params                  #"
    echo "#############################################"
    echo "1) Change the RTL password"
    echo "2) Change Bitcoin version"
    echo "3) Change LND version"
    echo ""
    echo -e "${BOLD}0) <- Back to main menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        if (change_rtl_password); then
          if [ $(are_services_up) -ne 1 ]; then
            $compose_command restart rtl
          fi
        fi
        ;;
      2)
        if (change_version "BITCOIN_CORE_VERSION" "bitcoin/bitcoin"); then
          $compose_command build bitcoin
          if [ $(are_services_up) -ne 1 ]; then
            $compose_command down
            $compose_command up -d
          fi
        fi
        ;;
      3)
        if (change_version "LND_VERSION" "lightningnetwork/lnd") ; then
          $compose_command build lnd
          if [ $(are_services_up) -ne 1 ]; then
            $compose_command down
            $compose_command up -d
          fi
        fi
        ;;
      0)
        display_menu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

connections_submenu() {
  while true; do
    echo "#############################################"
    echo "#              Connections                  #"
    echo "#############################################"
    echo "1) Display web addresses"
    echo "2) Display QR-code for Zeus Wallet"
    echo ""
    echo -e "${BOLD}0) <- Back to main menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        local local_ip=$(hostname -I | awk '{print $1}')
        echo -e "ELECTRS via TOR:     ${GREEN}${UNDERLINE}`cat ./data/tor/hidden_service_electrs/hostname`:50001${NC}${NC}"
        echo -e "Electrs (ssl):       https://$local_ip:50002"
        echo -e "LND Rest API (ssl):  https://$local_ip:8080"
        echo -e "RTL (ssl):           https://$local_ip:8081"
        echo -e "RTL (no ssl):        http://$local_ip:8082"
        if $docker_command ps --filter "name=awning_btcpay" --filter "status=running"|grep awning_btcpay > /dev/null; then
          echo -e "BTCPay (ssl):        https://$local_ip:8083"
          echo -e "BTCPay (no ssl):     http://$local_ip:8084"
        fi
        echo ""
        echo "Press any key to continue..."
        read -n 1 -s -r
        ;;
      2)
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          URI=`cat ./data/tor/hidden_service_lnd_rest/hostname` && $docker_command exec awning_lnd lndconnect --host $URI --port 8080
          echo ""
          echo "Press any key to get a code you can copy paste into the app."
          read -n 1 -s -r
          echo ""
          URI=`cat ./data/tor/hidden_service_lnd_rest/hostname` && $docker_command exec awning_lnd lndconnect -j  --host $URI --port 8080
        fi
        echo ""
        echo "Press any key to continue..."
        read -n 1 -s -r
        ;;
      0)
        display_menu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

utils_submenu() {
  while true; do
    echo "#############################################"
    echo "#                Utilities                  #"
    echo "#############################################"
    echo "1) Enter the Bitcoin container (bitcoin-cli)"
    echo "2) Enter the LND container (lncli)"
    echo "3) Restart services"
    echo "4) Rebuild docker images"
    echo "5) Run the SETUP tutorial"
    echo "6) Update Awning"
    echo ""
    echo -e "${BOLD}0) <- Back to main menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        $docker_command exec -it awning_bitcoin bash
        ;;
      2)
        $docker_command exec -it awning_lnd bash
        ;;
      3)
        restart_submenu
        ;;
      4)
        rebuild_submenu
        ;;
      5)
        setup_tutorial
        ;;
      6)
        read -p "Do you want to proceed? (y/n): " answer
        if [[ $answer =~ ^[Yy]$ ]]; then
          git stash
          git pull origin master
          git stash apply
          echo ""
          echo "You may need to rebuild and/or restart the Awning services"
          echo "Press any key to continue..."
          exec ./awning.sh
          exit
          read -n 1 -s -r
        elif [[ $answer =~ ^[Nn]$ ]]; then
          display_menu
        else
          echo "Invalid input."
        fi
        ;;
      0)
        display_menu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

restart_submenu() {
  while true; do
    echo "#############################################"
    echo "#                Restart                    #"
    echo "#############################################"
    echo "1) Restart the Awning node"
    echo "2) Restart Bitcoin"
    echo "3) Restart LND"
    echo ""
    echo -e "${BOLD}0) <- Back to utils menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          $compose_command down
          $compose_command up -d
        fi
        ;;
      2)
        $compose_command restart bitcoin
        ;;
      3)
        $compose_command restart lnd
        ;;
      0)
        utils_submenu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}
rebuild_submenu() {
  while true; do
    echo "#############################################"
    echo "#                Rebuild                    #"
    echo "#############################################"
    echo "1) Rebuild the node images"
    echo "2) Rebuild the node images without cache (can take up to one hour)"
    echo ""
    echo -e "${BOLD}0) <- Back to utils menu${NB}"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        $compose_command build
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      2)
        $compose_command build --no-cache
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      0)
        utils_submenu
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
  done
}

# Function to change RTL_PASSWORD
change_rtl_password() {
  echo -n "Enter new RTL password (press ENTER to keep current): "
  read new_rtl_password
  if [ ! -z "$new_rtl_password" ]; then
    sed -i "s/^RTL_PASSWORD=.*/RTL_PASSWORD=${new_rtl_password}/" .env
    echo -e "${GREEN}RTL password updated.${NC}"
    return 0
  else
    echo -e "${GREEN}RTL password unchanged.${NC}"
    return 1
  fi
}

# Function to change version
change_version() {
  local versions=$2
  versions=($(get_latest_versions $2))
  echo "Select $version_name:"
  for i in "${!versions[@]}"; do
    echo "$((i+1))) ${versions[$i]}"
  done
  echo -n "Choose a version (press ENTER to keep current v`grep '^'$1 .env | cut -d '=' -f 2`): "
  read version_index
  if [ ! -z "$version_index" ] && [ "$version_index" -le "${#versions[@]}" ]; then
    local new_version=$(echo ${versions[$((version_index-1))]} | sed 's/^v//')
    sed -i "s/^$1=.*/$1=$new_version/" .env
    echo -e "${GREEN}$version_name updated.${NC}"
    return 0
  else
    echo -e "${GREEN}$version_name unchanged.${NC}"
    return 1
  fi
}

# Function to check if docker-compose is installed
check_docker_compose() {
  if command -v docker-compose &> /dev/null; then
    if check_root_needed; then
      echo "sudo docker-compose"
    else
      echo "docker-compose"
    fi
  elif docker compose version &> /dev/null; then
    if check_root_needed; then
      echo "sudo docker compose"
    else
      echo "docker compose"
    fi
  else
    echo "None"
  fi
}

check_docker() {
  if check_root_needed; then
    echo "sudo docker"
  else
    echo "docker"
  fi
}

# Function to check if root is needed to run docker-compose
check_root_needed() {
  if docker ps &> /dev/null; then
    return 1  # Root is not needed
  else
    return 0  # Root is needed
  fi
}

setup_tutorial(){
  show_welcome
  choose_alias "1/7"
  insert_scb_repo "2/7"
  upload_scb_repo_deploy_key "3/7"
  choose_rtl_password "4/7"
  enable_btcpay "5/7"
  create_env_file
  create_compose
  compose_build "6/7"
  if [ $(are_services_up) -ne 0 ]; then
    $compose_command down
  fi
  $compose_command up -d
  check_lnd "6/7"
  display_menu
}

# Check if docker-compose or docker compose is available
compose_command=$(check_docker_compose)
if [ "$compose_command" == "None" ]; then
  echo "Neither docker-compose nor docker compose is installed. Please install one of them."
  exit 1
fi
docker_command=$(check_docker)

if [ -f "docker-compose.yml" ] && [ -f ".env" ]; then
  display_menu
else
  setup_tutorial
fi

