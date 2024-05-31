#!/bin/bash

RED='\033[0;31m'
ORANGE='\033[38;5;214m'
LIGHT_BLUE='\033[1;34m'
UNDERLINE='\033[4m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
BOLD='\e[1m'
NB='\e[0m'

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
  channel_backup_file="./data/lnd/chain/bitcoin/mainnet/channel.backup"
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

show_welcome() {
  echo -e "Welcome to the ${ORANGE}${BOLD}Awning${NB}${NC} setup tutorial!"
  echo -e "This script will guide you through setting up a full dockerized Bitcoin/LND/BTCPay server on your PC."
  if ! is_bitcoin_blockchain_downloaded; then
    echo -e "----------------"
    echo -e "It seems that you need to download the entire ${ORANGE}Bitcoin${NC} blockchain. This will take some time..."
    echo -e "If you already have the blockchain downloaded somewhere, please move it to ${UNDERLINE}./data/bitcoin/${NC} now."
  fi

  if ! is_lnd_initialized; then
    touch ./data/lnd/password.txt
    echo -e "----------------"
    echo -e "It seems that you need to initialize your ${LIGHT_BLUE}LND${NC} wallet."
    echo -e "If you already have your LND data somewhere, please move it to ${UNDERLINE}./data/lnd/${NC} now."
  fi

  echo -e ""
  echo "Press any key to continue..."
  read -n 1 -s -r
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

  while true; do
    echo -en "Enter your SSH repository address: "
    read SCB_REPO
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
    if check_root_needed; then
      sudo_cmd="sudo"
    else
      sudo_cmd=""
    fi

    echo -e "Generating the SSH key. This could take a few minutes. Please wait..."
    mkdir -p ./data/scb/.ssh

    # Generating ssh key
    $sudo_cmd docker run --rm -e MYUID=$MYUID -e MYGID=$MYGID -v "./data/scb/.ssh:/keys" debian:bookworm-slim sh -c "
    apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-client && \
      ssh-keygen -t rsa -b 2048 -f /keys/id_rsa -N '' && \
      chown $MYUID:$MYGID /keys/*" >/dev/null 2>&1

    # adding github public key fingerprints
    if [ ! -f ./data/scb/.ssh/known_hosts ]; then
      echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
      github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> ./data/scb/.ssh/known_hosts
    fi
  else
    echo -e "SSH key already present in ${UNDERLINE}./data/scb/.ssh/${NC}"
  fi

  echo "************************"
  cat ./data/scb/.ssh/id_rsa.pub
  echo "************************"
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

  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
  github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> ./data/scb/.ssh/known_hosts
  
  rm -rf ./data/scb/test
  cd ./data/scb
  while true; do
    echo -e "Performing test. Please wait..."
    # Test read
    GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=.ssh/known_hosts -o IdentitiesOnly=yes -i .ssh/id_rsa" git clone $SCB_REPO test #>/dev/null 2>&1
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
      # Test write
      GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=../.ssh/known_hosts -o IdentitiesOnly=yes -i ../.ssh/id_rsa" git push $SCB_REPO master #>/dev/null 2>&1
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
        GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=../.ssh/known_hosts -o IdentitiesOnly=yes -i ../.ssh/id_rsa" git push $SCB_REPO master #>/dev/null 2>&1
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
  while [ "$(docker inspect -f '{{.State.Running}}' awning_lnd_1 2>/dev/null)" != "true" ]; do
    echo -e "Waiting for LND container to start..."
    sleep $wait_interval
    elapsed=$((elapsed + wait_interval))
    if [ $elapsed -ge $timeout ]; then
      echo "Timed out waiting for the container to start."
      exit 1
    fi
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
    $docker_command exec -it awning_lnd_1 lncli create
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
RUN_BTCPAY=yes
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


# Function to update UID and GID in .env file
update_env_file() {
  local myuid=$1
  local mygid=$2
  sed -i "s/^UID=.*/UID=${myuid}/" .env
  sed -i "s/^GID=.*/GID=${mygid}/" .env
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
    echo -e "#               ${ORANGE}AWNING Menu${NC}                 #"
    echo "#############################################"
    if [ $(are_services_up) -ne 0 ]; then
      echo "1) Start the node"
    else
      echo "1) Stop the node"
    fi
    echo "2) Check the logs (CRTL+C to exit)"
    echo "3) Change the RTL password"
    echo "4) Change Bitcoin version"
    echo "5) Change LND version"
    echo "6) Display web addresses"
    echo "7) Display connection URL for Zeus Wallet"
    echo "8) Restart"
    echo "9) Update Awning"
    echo "0) Exit"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option

    case $option in
      1)
        if [ $(are_services_up) -ne 0 ]; then
          echo "Starting the node..."
          $compose_command up -d
        else
          echo "Stopping the node..."
          $compose_command down
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
        change_rtl_password
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command restart rtl
        fi
        ;;
      4)
        change_version "BITCOIN_CORE_VERSION" "bitcoin/bitcoin"
        $compose_command build bitcoin
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      5)
        change_version "LND_VERSION" "lightningnetwork/lnd"
        $compose_command build lnd
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      6)
        echo -e "ELECTRS via TOR:     ${GREEN}${UNDERLINE}`cat ./data/tor/hidden_service_electrs/hostname`:50001${NC}${NC}"
        echo -e "Electrs (ssl):       https://localhost:50002"
        echo -e "LND Rest API (ssl):  https://localhost:8080"
        echo -e "RTL (ssl):           https://localhost:8081"
        echo -e "RTL (no ssl):        http://localhost:8082"
        echo -e "BTCPay (ssl):        https://localhost:8083"
        echo -e "BTCPay (no ssl):     http://localhost:8084"
        echo "Press any key to continue..."
        read -n 1 -s -r
        ;;
      7)
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          URI=`cat ./data/tor/hidden_service_lnd_rest/hostname` && $docker_command exec awning_lnd_1 lndconnect --host $URI --port 8080
        fi
        echo "Press any key to continue..."
        read -n 1 -s -r
        ;;
      8)
        restart_submenu
        ;;
      9)
         $compose_command down
         git stash
         git pull
         git stash apply
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

logs_submenu(){
  while true; do
    echo "#############################################"
    echo -e "#           Logs (CRTL+C to exit)          #"
    echo "#############################################"
    echo "1) All the logs"
    echo "2) Bitcoin logs"
    echo "3) LND logs"
    echo "4) Electrs logs"
    echo "0) <-- Back to main menu"
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
    echo "4) Rebuild the node images"
    echo "5) Rebuild the node images without cache (can take up to one hour)"
    echo "6) Restart the SETUP tutorial"
    echo "0) <-- Back to main menu"
    echo "#############################################"
    echo ""
    echo -n "Choose an option: "
    read option
    case $option in
      1)
        if [ $(are_services_up) -ne 0 ]; then
          echo -e "${RED}Node is not running!${NC}"
        else
          $compose_command restart
        fi
        ;;
      2)
        $compose_command restart bitcoin
        ;;
      3)
        $compose_command restart lnd
        ;;
      4)
        $compose_command build
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      5)
        $compose_command build --no-cache
        if [ $(are_services_up) -ne 1 ]; then
          $compose_command down
          $compose_command up -d
        fi
        ;;
      6)
        setup_tutorial
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

# Function to change RTL_PASSWORD
change_rtl_password() {
  echo -n "Enter new RTL password (press ENTER to keep current): "
  read new_rtl_password
  if [ ! -z "$new_rtl_password" ]; then
    sed -i "s/^RTL_PASSWORD=.*/RTL_PASSWORD=${new_rtl_password}/" .env
    echo -e "${GREEN}RTL password updated.${NC}"
  else
    echo -e "${GREEN}RTL password unchanged.${NC}"
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
  else
    echo -e "${GREEN}$version_name unchanged.${NC}"
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
  insert_scb_repo "1/6"
  upload_scb_repo_deploy_key "2/6"
  choose_rtl_password "3/6"
  enable_btcpay "4/6"
  create_env_file
  create_compose
  compose_build "5/6"
  $compose_command up -d
  check_lnd "6/6"
  display_menu
}

# Check if docker-compose or docker compose is available
compose_command=$(check_docker_compose)
if [ "$compose_command" == "None" ]; then
  echo "Neither docker-compose nor docker compose is installed. Please install one of them."
  exit 1
fi
docker_command=$(check_docker)

if [ ! -f .env ]; then
  setup_tutorial
else
  display_menu
fi

