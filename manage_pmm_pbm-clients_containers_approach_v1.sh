#!/bin/bash
#
# Global variables 
#
VERSION="BETA 1.0, Integrate the Open Source Percona Platform to monitor and backup using Percona MongoDB containerized"
WARNING_MESSAGE="WARNING There is no warranty on this script, use this script at your own risk"
INFORMATION_MESSAGE="This script has not been fully optimized"
SCRIPT_VERSION="1.0"
# 
# This script has a dependency, being the MongoDB instance was created with create_mongodb_container_v5.x.sh 
SOLUTION_HOME_DIR='/mongodb'
#
PERCONA_MONGODB_PMM_USERNAME=''
PERCONA_MONGODB_PMM_PASSWORD=''
MONGODB_ADM_USER=''
MONGODB_ADM_PASSWORD=''
#
DUMMY_RESP=""
#
# uncomment the next line to enable full debugging
# set -o xtrace
# set commands 
# -e	-o errexit	Exit immediately if a command fails.
# -u	-o nounset	Treat unset variables as an error.
# -x	-o xtrace	Print each command before executing it (debugging).
# -v	-o verbose	Print shell input lines as they are read.
# -f	-o noglob	Disable filename expansion (globbing).
# -n	-o noexec	Read script but don’t execute (syntax check).
# -C	-o noclobber	Prevent overwriting existing files with >.
# -b	-o notify	Notify immediately when background jobs finish.
# -T	-o functrace	Allow tracing/debugging in functions and sub shells.
# -E	-o errtrace	Ensure trap ERR applies in sub shells.
# -H	-o histexpand	Enable ! history expansion.
# -m	-o monitor	Enable job control (default in interactive shells).
# 
# 
# set +e  # Disable "exit on error"
# set +x  # Disable debugging (tracing)
#
##
set -Eeuo pipefail
##
trap cleanup SIGINT SIGTERM ERR
##
# Set defaults global variables
#
MONGODB_ADM_USER=''
#
#######################################
# Clean up setup if interrupt.
#######################################
cleanup() {
  msg "\n\n\nDoing clean up ... and exiting"
  trap - SIGINT SIGTERM ERR EXIT
  exit
}
#######################################
# Prints message and exit with code.
# Arguments:
#   message string;
#   exit code.
# Outputs:
#   writes message to stderr.
#######################################
die() {
  local message=$1
  local code=${2-1} # default exit status 1
  msg "$message"
  exit "$code"
}
#######################################
# Defines colours for output messages.
#######################################
#PURPLE='\033[0;35m'
#CYAN='\033[0;36m'
#RED='\033[0;31m'
#BLACK='\033[0;30m'
#BACKGROUNDWHITE='\033[0;47m'
#BOLD='\033[1m'
#REVERSED='\033[7m'
#NC='\033[0m'
#GREEN='\033[0;32m'
#IRED='\033[0;91m'
#URED='\033[4;31m'  
#ORANGE='\033[38;5;214m'
#YELLOW='\033[0,33m'
#PURPLE='\033[0;35m'
#BLUE='\033[0;34m'
#
setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NC='\033[0m' RED='\033[0;31m'  ORANGE='\033[0;33m'  BOLD='\033[1m'
    CYAN='\033[0;36m' 
  else
    NC='' RED=''  ORANGE='' CYAN='' BOLD=''
  fi
}
#######################################
# Prints message to stderr with new line at the end and 2 blank lines
#######################################
msg() {
  echo >&2 -e "${1-}"
}

#
# Quick validation because we need to runt this script in the same folder area as the script that create the MongoDB in containers 
# as the $SOLUTION_HOME_DIR/scripts folder is shared between these 2 scripts 
#

cd "$SOLUTION_HOME_DIR" || { msg "${RED}This folder $SOLUTION_HOME_DIR was NOT found ${NC}"; msg "${RED}It is imperative that this folder exist ${NC}"; exit 1; }

# ========== start of functions sections =============
#
# ++ function wait_with_message
#
function wait_with_message {
  local wait_time="$1"
  local message="$2"
  #
  if [[ "$wait_time" =~ ^[0-9]+$ ]]; then # Check if input is a number
    if [[ -n "$message" ]]; then #if a message was provided
      msg "${ORANGE}waiting $wait_time seconds: $message ${NC}"
    else
       msg "${ORANGE}waiting $wait_time seconds ${NC}"
    fi

    local i=0
    while [ "$i" -lt "$wait_time" ]; do
      sleep 1
      echo -n "."
      i=$((i + 1))
    done

    echo
  else
    msg "Invalid input. Please enter a number."
    return 1 # Indicate an error
  fi
}
#
# ++ function pmm-server
#
function function_pmm-server {
# 
  msg "\n${CYAN} Before we start to do anything ...  ${NC}"  
  msg  "${CYAN} We need to collect ${BOLD} ${ORANGE} username / password of an PMM Server admin account${NC}"
  msg "${CYAN} As this will be required latter in this script ${NC}"

  msg  "\nPercona username for the pmm server admin account to be used  (e.g. admin) ?" 
  read -r -p "Please enter your response " RESP_PERCONA_SERVER_USERNAME

 if [ "$RESP_PERCONA_SERVER_USERNAME" =  "" ] ; then
    die "${RED}  Percona username for the pmm server value can not be empty ${NC}"
 else
   PERCONA_SERVER_USERNAME=$RESP_PERCONA_SERVER_USERNAME
 fi 
   
  msg "\nPercona password for the pmm server admin account to be used  ?"
  msg "${BOLD}Password characters will not be displayed${NC}" 

  read -r -s -p "Please enter your response  " RESP_PERCONA_SERVER_PASSWORD

 if [ "$RESP_PERCONA_SERVER_PASSWORD" = "" ] ; then
    die "${RED} Percona password for the pmm server value can not be empty ${NC}"
 else
    PERCONA_SERVER_PASSWORD=$RESP_PERCONA_SERVER_PASSWORD
 fi 
}
#######################################
# ++ function setup_configure_pmm-client 
#######################################
function function_setup_configure_pmm-client {
     #
     # $1 = container name 
     # $2 = ppm-server IP address
     # $3 = pmm-server admin account 
     # $4 = pmm-server admin password 
     # $5 = instance version represent in the PMM Server GUI 
     #
     #
     local CONTAINER_NAME="$1"
     local PMM_SERVER_IP_DESTINATION="$2"
     local PMM_SERVER_USERNAME="$3"
     local PMM_SERVER_PASSWORD="$4"
     local INSTANCE_VERSION="$5"
     local TEMP_NAME=""

     #
     #
     # before we start , need to get the container IP information
     #
     IP_OF_CONTAINER=$(docker exec "${CONTAINER_NAME}"  hostname -i)
     CONTAINER_HOSTNAME=$(docker exec "${CONTAINER_NAME}"  hostname -s)
     TEMP_NAME=${INSTANCE_VERSION}_$(hostname -s)_${CONTAINER_NAME}
     #
     echo
     msg "${ORANGE}Container information :  ${NC} "
     msg "          Container name: $CONTAINER_NAME , hostname inside the container: $CONTAINER_HOSTNAME, IP of the container:  $IP_OF_CONTAINER" 
     msg "Container name: $CONTAINER_NAME , hostname inside the container: $CONTAINER_HOSTNAME, IP of the container:  $IP_OF_CONTAINER" >>  /tmp/container_information.txt
     echo
   
     msg 
     msg "${ORANGE} Let's go start the pmm-agent first  ${NC} "
     echo
     function_start_pmm-client_within_container "$CONTAINER_NAME"
     echo
     msg "${ORANGE}Setup and configure pmm-client/pmm-agent (using config_pmm_agent.js) inside the docker $CONTAINER_NAME container ${NC} "  
     msg 
     tee "$SOLUTION_HOME_DIR"/scripts/config_pmm_agent_setup.js 1> /dev/null <<EOF
export PMM_AGENT_SETUP_NODE_NAME=$TEMP_NAME
export PMM_AGENT_SETUP_NODE_TYPE=container
export PMM_AGENT_CONFIG_FILE=/usr/local/percona/pmm/config/pmm-agent.yaml
#export PMM_AGENT_SETUP_METRICS_MODE=push
export PMM_AGENT_SETUP_REGION=${INSTANCE_VERSION}_Ottawa
export PMM_AGENT_SETUP_NODE_MODEL=VM
export PMM_AGENT_SETUP=1
env | grep PMM
#rm -f /usr/local/percona/pmm2/config/pmm-agent.yaml
#touch /usr/local/percona/pmm2/config/pmm-agent.yaml
#chown pmm-agent:pmm-agent /usr/local/percona/pmm2/config/pmm-agent.yaml
pmm-agent setup --force --server-insecure-tls --server-address="${PMM_SERVER_IP_DESTINATION}:443" --server-username="$PMM_SERVER_USERNAME" --server-password="$PMM_SERVER_PASSWORD"
EOF
    #
    cat "$SOLUTION_HOME_DIR"/scripts/config_pmm_agent_setup.js
    #
     CHECK_PMM_AGENT_RUNNING=$(docker exec -t -u 0 "$CONTAINER_NAME" bash -c 'ps aux | pgrep pmm-agent')
     
     if [ "$CHECK_PMM_AGENT_RUNNING" = "" ] ; then 
           msg "\n${ORANGE} Could not find the pmm-agent process running within the container $CONTAINER_NAME,  let's go start the pmm-agent first ${NC} "
           echo
           function_start_pmm-client_within_container "$CONTAINER_NAME"
           wait_time=1
           wait_with_message
     else
           msg "\n${ORANGE} It appears pmm_agent is running withe the container $CONTAINER_NAME as we found PID $$CHECK_PMM_AGENT_RUNNING ${NC} "
           msg 
     fi       
     #
    set -o xtrace
    docker cp "$SOLUTION_HOME_DIR"/scripts/config_pmm_agent_setup.js "$CONTAINER_NAME":/tmp/config_pmm_agent_setup.js
    docker exec -t "$CONTAINER_NAME" chmod +x  /tmp/config_pmm_agent_setup.js
    docker exec -t -u 0 "$CONTAINER_NAME" bash -c /tmp/config_pmm_agent_setup.js
    #docker exec -t "$CONTAINER_NAME" rm -f /tmp/config_pmm_agent_setup.js
    #rm -f "$SOLUTION_HOME_DIR"/scripts/config_pmm_agent_setup.js
    set +o xtrace
    #docker exec -t "$CONTAINER_NAME" pmm-agent setup --force --server-insecure-tls --config-file=/usr/local/percona/pmm/config/pmm-agent.yaml --server-address="${PMM_SERVER_IP_DESTINATION}:443" --server-username="$PMM_SERVER_USERNAME" --server-password="$PMM_SERVER_PASSWORD" "$IP_OF_CONTAINER" container "$TEMP_NAME"
#
}
#######################################
# ++ function function_get_instance_version
#######################################
function function_get_instance_version {
#
#

  msg "\n${CYAN} Found a strange issue on the PMM Server GUI side, if reconfiguring the pmm-agent multiple times ${NC}"
  msg "${CYAN} The system summary says no agents found, although on the client (pmm-admin status) side every thing looks good ${NC}"
  msg "${CYAN} Will try and address the issues ona future release of the solution, but for now the work around is the add a instance number${NC}"

  msg "\nWat will th ebe instance number (e.g. 1, 2, 3, ... max of 100)  ?"
  read -r -p "Please enter your response: " RESP_INSTANCE_VERSION

  if [[ "$RESP_INSTANCE_VERSION" =~ ^[0-9]+$ ]]; then
     if (( RESP_INSTANCE_VERSION >= 1 && RESP_INSTANCE_VERSION <= 100 )); then
      msg  "\n✅ Valid number: $RESP_INSTANCE_VERSION\n"
      INSTANCE_VERSION="$RESP_INSTANCE_VERSION"
    else
      msg  "\n❌ Number out of range (1–100)\n"
    fi
  else
    msg "\n❌ $RESP_INSTANCE_VERSION Not a valid number\n"
  fi
}
#######################################
# ++ function function_setup_configure_pmm-client_force 
#######################################
function function_setup_configure_pmm-client_force {
     #
     # $1 = container name 
     # $2 = ppm-server IP address
     # $3 = pmm-server admin account 
     # $4 = pmm-server admin password      
     #
     #
     local CONTAINER_NAME="$1"
     local PMM_SERVER_IP_DESTINATION="$2"
     local PMM_SERVER_USERNAME="$3"
     local PMM_SERVER_PASSWORD="$4"
     local TEMP_NAME=""
     #
     # before we start , need to get the container IP information
     #
     IP_OF_CONTAINER=$(docker exec "${CONTAINER_NAME}"  hostname -i)
     CONTAINER_HOSTNAME=$(docker exec "${CONTAINER_NAME}"  hostname -s)
     TEMP_NAME=$(hostname -s)_${CONTAINER_NAME}

     msg "\n${ORANGE}Container information:  ${NC} "
     msg "          Container name: $CONTAINER_NAME , hostname inside the container: $CONTAINER_HOSTNAME, IP of the container:  $IP_OF_CONTAINER" 
     msg "Container name: $CONTAINER_NAME , hostname inside the container: $CONTAINER_HOSTNAME, IP of the container:  $IP_OF_CONTAINER" >>  /tmp/container_information.txt
     #
     CHECK_PMM_AGENT_RUNNING=$(docker exec -t -u 0 "$CONTAINER_NAME" bash -c 'ps aux | pgrep pmm-agent')
     
     if [ "$CHECK_PMM_AGENT_RUNNING" = "" ] ; then 
           msg "\n${ORANGE} Could not find the pmm-agent running within the container $CONTAINER_NAME,  Let's go start the pmm-agent first ${NC}\n"
           function_start_pmm-client_within_container "$CONTAINER_NAME"
           wait_time=1
           wait_with_message
     else
           msg "\n${ORANGE} IT appears pmm_agent is running withe the container $CONTAINER_NAME as we found PID $$CHECK_PMM_AGENT_RUNNING ${NC}\n"
     fi       

     msg "\n${ORANGE} pmm-admin config, inside the docker  $CONTAINER_NAME container ${NC}\n"

     set -o xtrace
     docker exec -t "$CONTAINER_NAME" pmm-admin config --force "$IP_OF_CONTAINER" container "$TEMP_NAME" --server-insecure-tls --server-url=https://"${PMM_SERVER_USERNAME}:${PMM_SERVER_PASSWORD}@${PMM_SERVER_IP_DESTINATION}:443" 
     set +o xtrace
     docker exec -t "$CONTAINER_NAME" pmm-admin status 
     #
     #
}
#######################################
# ++ function start_pmm-client_within_container 
#######################################
function function_start_pmm-client_within_container  {
       #
       # $1 = container name 
       #
       local CONTAINER_NAME="$1"
       #
       msg "\n${ORANGE}Start pmm-agent inside the docker $CONTAINER_NAME container ${NC}\n"
       #
       if [ -f "$SOLUTION_HOME_DIR/scripts/start_pmm_file.sh"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh, deleting it\n"
          rm -f "$SOLUTION_HOME_DIR/scripts/start_pmm_file.sh" 
      fi    
      msg "\ncreating the file $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh\n"
      #
      tee $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh  1> /dev/null <<EOF
#!/bin/bash
#
nohup pmm-agent --config-file=/usr/local/percona/pmm/config/pmm-agent.yaml > /log/pmm-agent-$CONTAINER_NAME.log 2>&1 &
EOF
#
      docker cp $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh  "$CONTAINER_NAME:"/start_pmm_file.sh

      rm $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh # deleting the file because is's got a password in it 
      
      set -o xtrace
      docker exec "$CONTAINER_NAME" bash -c "chmod +x start_pmm_file.sh"
      docker exec "$CONTAINER_NAME" bash -c "/start_pmm_file.sh"
      set +o xtrace
}
#######################################
# ++ function pmm-client-agent
#######################################
function function_pmm-client-agent {
# 
  msg "\n${CYAN} Before we start to do anything ...  ${NC}"  
  msg "${CYAN} We need to collect ${BOLD}${ORANGE} Percona PMM agent username / password previously created ${NC}${CYAN}in the MongoDB instance${NC}"
  msg "${CYAN} As this will be required in this script ${NC}"

  msg "\nPercona MongoDB username for the pmm agent to be used  (e.g. pmm) ?" 
  read -r -p "Please enter your response " RESP_PERCONA_MONGODB_PMM_USERNAME

 if [ "$RESP_PERCONA_MONGODB_PMM_USERNAME" =  "" ] ; then
    die "${RED}  Percona MongoDB username for the pmm agent value can not be empty ${NC}"
 else
     PERCONA_MONGODB_PMM_USERNAME=$RESP_PERCONA_MONGODB_PMM_USERNAME
 fi 
  msg "\nPercona MongoDB password for the pmm agent to be used  ?"
  msg "${BOLD}Password characters will not be displayed${NC}"
  read -r -s -p "Please enter your response  " RESP_PERCONA_MONGODB_PMM_PASSWORD

 if [ "$RESP_PERCONA_MONGODB_PMM_PASSWORD" = "" ] ; then
    die "${RED} Percona MongoDB password for the pmm agent value can not be empty ${NC}"  
 else
    PERCONA_MONGODB_PMM_PASSWORD=$RESP_PERCONA_MONGODB_PMM_PASSWORD
 fi 
}
#######################################
# ++ check_cash_function_pmm-client-agent
#######################################
function check_cashed_function_pmm-client-agent {
    #
    # 
    #
    if [ "$PERCONA_MONGODB_PMM_USERNAME" = "" ]; then
         function_pmm-client-agent
    else 
        msg    
        msg "      Currently (information temporary cached within this script only) MongoDB PMM Username: ${BOLD}$PERCONA_MONGODB_PMM_USERNAME${NC}"
        msg "      Currently (information temporary cached within this script only) MongoDB PMM Password: ${BOLD}$PERCONA_MONGODB_PMM_PASSWORD${NC}"
        
        msg "\nIs the above information correct ?"
        read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "N" ] ; then
           function_pmm-client-agent 
        else
           msg "\nLet's continue ..."
      fi    
    fi
}
#######################################
# ++ function mongodb_cluster_name
#######################################
function function_mongodb_cluster_name {
  #
  msg "\n${CYAN} We need to collect the the MongoDB shard cluster name (e.g. SQL105 / JFROG  ...)${NC}"
  msg "${CYAN} required latter in this script ${NC}"

  msg "\nMongoDB shard cluster name (e.g. SQL105  / JFROG  ...) "
  read -r -p "Please enter your response " RESP_MONGODB_SHARD_CLUSTER_NAME

 if [ "$RESP_MONGODB_SHARD_CLUSTER_NAME" =  "" ] ; then
    die "${RED} MongoDB shard cluster name value can not be empty ${NC}"
 else
    MONGODB_SHARD_CLUSTER_NAME=$RESP_MONGODB_SHARD_CLUSTER_NAME
 fi 
}
#######################################
# ++ function pmm_server_ip
#######################################
function function_pmm_server_ip {
  #
  msg "\n${CYAN} We need to collect the Percona Server IP (pmm-server) address (e.g.  192.168.1.31)${NC}"
  msg "${CYAN} required latter in this script ${NC}"
#
  msg "\nIP address of the Percona pmm-server (e.g. 192.168.1.31) ?"
  read -r -p "Please enter your response " RESP_PMM_SERVER_IP

 if [ "$RESP_PMM_SERVER_IP" =  "" ] ; then
    die "${RED} IP address of the Percona pmm-server value can not be empty ${NC}"
 else
    PMM_SERVER_IP=$RESP_PMM_SERVER_IP
 fi 
}
#######################################
# ++ function percona_mongodb_cluster_env
#######################################
function function_percona_mongodb_cluster_env {
#
#
  msg "\n${CYAN} We need to collect the MongoDB Cluster Environment (PROD/DEV/TEST ...) within PERCONA${NC}"
  msg "${CYAN} required latter in this script ${NC}"
#
  msg "\nPercona pmm-server MongoDB cluster name (e.g. PROD / TEST ...) ?"
  read -r -p "Please enter your response " RESP_PERCONA_MONGODB_CLUSTER_ENV

 if [ "$RESP_PERCONA_MONGODB_CLUSTER_ENV" = "" ] ; then
   die "${RED} Percona pmm-server MongoDB cluster name can not be empty ${NC}"
 else
    PERCONA_MONGODB_CLUSTER_ENV=$RESP_PERCONA_MONGODB_CLUSTER_ENV
 fi 
}
#######################################
# ++ function register_mongodb_with_pmm-client
#######################################
function function_register_mongodb_with_pmm-client {
     #
     # $1 = TEMP_CONTAINER_NAME
     # $2 = TEMP_PERCONA_MONGODB_PMM_USERNAME 
     # $3 = TEMP_PERCONA_MONGODB_PMM_PASSWORD 
     # $4 = TEMP_MONGODB_SHARD_CLUSTER_NAME
     # $5 = TEMP_PERCONA_MONGODB_CLUSTER_ENV 
     #
     local TEMP_CONTAINER_NAME="$1"
     local TEMP_PERCONA_MONGODB_PMM_USERNAME="$2"
     local TEMP_PERCONA_MONGODB_PMM_PASSWORD="$3"
     local TEMP_MONGODB_SHARD_CLUSTER_NAME="$4"
     local TEMP_PERCONA_MONGODB_CLUSTER_ENV="$5"

     msg "\n${ORANGE} Registering MongoDB monitoring service inside the docker $TEMP_CONTAINER_NAME container ${NC} "  

     set -o xtrace
     docker exec "$TEMP_CONTAINER_NAME" pmm-admin add mongodb \
       --username="$TEMP_PERCONA_MONGODB_PMM_USERNAME" \
       --password="$TEMP_PERCONA_MONGODB_PMM_PASSWORD"  \
       --service-name="${TEMP_MONGODB_SHARD_CLUSTER_NAME}"_"${TEMP_CONTAINER_NAME}" \
       --enable-all-collectors \
       --cluster "$TEMP_MONGODB_SHARD_CLUSTER_NAME" \
       --environment="$TEMP_PERCONA_MONGODB_CLUSTER_ENV" 
     set +o xtrace
}
#######################################
# ++ function function_setup_configure_pmm 
#######################################
function function_setup_configure_pmm {
   #
   msg "\nTriggering the action of the setup/configure of pmm-client / pmm-agent inside the different docker containers ..."
   read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
    msg "\n${CYAN} Skipping function_setup_configure_pmm ${NC}\n"
  else  
     #
     # we require some input
     #
     function_pmm-server
     function_pmm_server_ip 
     function_get_instance_version
     #
     function_setup_configure_pmm-client "router-01" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "router-02" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "mongo-config-01" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "mongo-config-02" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "mongo-config-03" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-01-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-01-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-01-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-02-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-02-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-02-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-03-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-03-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"
     function_setup_configure_pmm-client "shard-03-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" "$INSTANCE_VERSION"     
  fi 
}
#######################################
# ++ function function_setup_configure_pmm_force 
#######################################
function function_setup_configure_pmm_force {
  #
  msg "\nTriggering the action of the setup/configuring pmm-client / pmm-agent with --force inside the different docker containers ..."
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
     msg "\n${CYAN} Skipping function_setup_configure_pmm_force ${NC}\n"
  else   
     #
     # we require some input
     #
     function_pmm-server
     function_pmm_server_ip 
     #
     function_setup_configure_pmm-client_force "router-01" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" function_get_instance_version
     function_setup_configure_pmm-client_force "router-02" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  
     function_setup_configure_pmm-client_force "mongo-config-01" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "mongo-config-02" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "mongo-config-03" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  
     function_setup_configure_pmm-client_force "shard-01-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "shard-01-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "shard-01-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  
     function_setup_configure_pmm-client_force "shard-02-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "shard-02-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  
     function_setup_configure_pmm-client_force "shard-02-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"   
     function_setup_configure_pmm-client_force "shard-03-node-a" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"  
     function_setup_configure_pmm-client_force "shard-03-node-b" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD" 
     function_setup_configure_pmm-client_force "shard-03-node-c" "$PMM_SERVER_IP" "$PERCONA_SERVER_USERNAME" "$PERCONA_SERVER_PASSWORD"         
  fi 
}
#######################################
# ++ function function_start_pmm 
#######################################
function function_start_pmm {
  #
  msg "\nTriggering the action to start the pmm-client (pmm-agent) inside the different docker containers ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ]  ; then
     msg "\n${CYAN} Answer was not Y or y, skipping  function_start_pmm ${NC}\n"
  else   
     #
     function_start_pmm-client_within_container "router-01" 
     function_start_pmm-client_within_container "router-02" 
     function_start_pmm-client_within_container "mongo-config-01" 
     function_start_pmm-client_within_container "mongo-config-02" 
     function_start_pmm-client_within_container "mongo-config-03" 
     function_start_pmm-client_within_container "shard-01-node-a" 
     function_start_pmm-client_within_container "shard-01-node-b" 
     function_start_pmm-client_within_container "shard-01-node-c" 
     function_start_pmm-client_within_container "shard-02-node-a" 
     function_start_pmm-client_within_container "shard-02-node-b"  
     function_start_pmm-client_within_container "shard-02-node-c"   
     function_start_pmm-client_within_container "shard-03-node-a" 
     function_start_pmm-client_within_container "shard-03-node-b" 
     function_start_pmm-client_within_container "shard-03-node-c"  
  fi 
}
#######################################
# ++ function_register_mongodb_services
#######################################
function function_register_mongodb_services {
  msg "\nTriggering the action the registration of the MongoDB ppm-client services  inside the different docker containers ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
    msg "\n${CYAN} Skipping function_register_mongodb_services ${NC}\n"
  else
     #function_pmm-client-agent 
     check_cashed_function_pmm-client-agent
     function_mongodb_cluster_name 
     function_percona_mongodb_cluster_env
     #
     function_register_mongodb_with_pmm-client "router-01" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "router-02" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "mongo-config-01" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "mongo-config-02" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "mongo-config-03" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV"
     function_register_mongodb_with_pmm-client "shard-01-node-a" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-01-node-b" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-01-node-c" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-02-node-a" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-02-node-b" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-02-node-c" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-03-node-a" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV" 
     function_register_mongodb_with_pmm-client "shard-03-node-b" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV"
     function_register_mongodb_with_pmm-client "shard-03-node-c" "$PERCONA_MONGODB_PMM_USERNAME" "$PERCONA_MONGODB_PMM_PASSWORD" "$MONGODB_SHARD_CLUSTER_NAME" "$PERCONA_MONGODB_CLUSTER_ENV"        
  fi
}
#######################################
# ++ function function_check_pmm-client_within_container
#######################################
function function_check_pmm-client_within_container {
    #
    # $1 = CONTAINER_NAME
    local CONTAINER_NAME="$1"
    #
    msg "\n${ORANGE}${BOLD} ***************** looking inside container $CONTAINER_NAME  ************************ ${NC}\n"
    #
    docker exec "$CONTAINER_NAME" ps -eo pid,comm 

    CHECK_AGENT_PMM=$(docker exec "$CONTAINER_NAME" ps -eo pid,comm | awk '{print $2}' | grep -i pmm-agent)

    if [ "$CHECK_AGENT_PMM" = "" ]; then
       msg "\n${ORANGE}pmm-agent linux process is missing in docker container $CONTAINER_NAME${NC}" 
       msg "\nIt appears the pmm-agent process inside the different docker containers $CONTAINER_NAME is missing"
       msg "\nDo you want to re-initiate / restart that process ?"
       read -r -p "Please enter your response (Y/N) default: [N] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "Y" ] ; then
          function_start_pmm-client_within_container "$CONTAINER_NAME"
       fi
    else
         msg "\n${ORANGE}${BOLD} pmm-agent linux process was found in the docker container $CONTAINER_NAME${NC}\n" 
    fi
    msg "\n${BOLD}==> docker exec $CONTAINER_NAME pmm-admin status results ${NC}\n" 
    docker exec "$CONTAINER_NAME" pmm-admin status

    msg "\n${BOLD}==> docker exec $CONTAINER_NAME pmm-admin list results ${NC}\n" 
    docker exec "$CONTAINER_NAME" pmm-admin list
}
#######################################
# ++ function function_pbm-client_command 
#######################################
function function_pbm-client_command {
  # $1 = container name
  # $2 = PBM_MONGODB_URI
  # $3 = PBM_COMMAND
  # $4 = PBM_COMMAND_FLAG (unused in this function)
  local CONTAINER_NAME="$1"
  local BPM_MONGODB_URI="$2"
  local PBM_COMMAND="$3"

  msg "\n${ORANGE}pbm $PBM_COMMAND within $CONTAINER_NAME container${NC}\n"

  PBM_COMMAND=${PBM_COMMAND,,} # convert to lowercase

  case "$PBM_COMMAND" in
    status|list|config|logs)
      docker exec -t "$CONTAINER_NAME" ls -lht /backup
      docker exec -t "$CONTAINER_NAME" pbm "$PBM_COMMAND" --mongodb-uri "$BPM_MONGODB_URI"
      ;;
    *)
      echo "Invalid PBM command: $PBM_COMMAND"
      return 1 # Indicate an error
      ;;
  esac
}
#######################################
# ++ function function_pbm-execute_backup
#######################################
function function_pbm-execute_backup {
  # $1 = container name
  # $2 = PBM_MONGODB_URI
  local CONTAINER_NAME="$1"
  local BPM_MONGODB_URI="$2"

  msg "\n${ORANGE}pbm backup using this container: $CONTAINER_NAME${NC}"
  msg "\nTriggering the action to start backup, is the above command correct ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case
  if [ "$RESP" = "N" ]; then
    msg "\n${CYAN} Skipping function_pbm-execute_backup${NC}\n"
  else
    read -r -p "Is this a logical or physical PBM backuo? (1 = logical, 2 = physical): " WHAT_KIND_OF_PBM_RESTORE
    case "$WHAT_KIND_OF_PBM_RESTORE" in
    1)
        msg "Performing a logical restore..."
        KIND_OF_PBM_RESTORE="logical"
        PBM_BACKUP_COMMAND_FLAG="--type=logical"
        ;;
    2)
        msg "Performing a physical restore..."
        KIND_OF_PBM_RESTORE="physical"
        PBM_BACKUP_COMMAND_FLAG="--type=physical"
        ;;
    *)
        msg "Invalid value entered: for WHAT_KIND_OF_PBM_RESTORE (valid values are 1 or 2) and this was entered: $WHAT_KIND_OF_PBM_RESTORE"
        return 1
        ;;
    esac

    set -x # Enable xtrace (same as set -o xtrace)
    docker exec -t "$CONTAINER_NAME" pbm backup "$PBM_BACKUP_COMMAND_FLAG" --mongodb-uri "$BPM_MONGODB_URI"
    set +x # Disable xtrace (same as set +o xtrace)

    msg "\n${CYAN}Because the pbm backup activity in ASYNC, we need to check the status and logs to confirm the backup completed, before moving forward ${NC}\n"
 
    local CHECK_RESTORE="" # Initialize CHECK_RESTORE
    while [ "$CHECK_RESTORE" != "3" ]; do
      msg "\n( 1 = check status, 2 = check logs, 3 = exit )" 
      read -r -p "Please enter task to perform: " CHECK_RESTORE

      msg "\nSelected task number was : $CHECK_RESTORE\n"

      if [ "$CHECK_RESTORE" = "1" ]; then
        function_pbm-client_command "$CONTAINER_NAME" "$BPM_MONGODB_URI" "status"
      elif [ "$CHECK_RESTORE" = "2" ]; then
        function_pbm-client_command "$CONTAINER_NAME" "$BPM_MONGODB_URI" "logs"
      elif [ "$CHECK_RESTORE" != "3" ]; then
        msg "Invalid input. Please enter 1, 2, or 3."
      fi
    done
  fi
}
#######################################
# ++ function function_pmm-admin_which_container
#######################################
function function_pmm-admin_command_which_container {
    #
    local CHECK_RESP_CONTAINER=''
    
    msg "\n${CYAN} option 1 for container router-01 ${NC}"
    msg "${CYAN} option 2 for container router-02  ${NC}"
    msg "${CYAN} option 3 for container mongo-config-01 ${NC}"
    msg "${CYAN} option 4 for container mongo-config-02 ${NC}"
    msg "${CYAN} option 5 for container mongo-config-03 ${NC}"
    msg "${CYAN} option 6 for container shard-01-node-a ${NC}"   
    msg "${CYAN} option 7 for container shard-01-node-b ${NC}"
    msg "${CYAN} option 8 for container shard-01-node-c ${NC}"  
    msg "${CYAN} option 9 for container shard-02-node-a ${NC}"   
    msg "${CYAN} option 10 for container shard-02-node-b ${NC}"      
    msg "${CYAN} option 11 for container shard-02-node-c ${NC}"   
    msg "${CYAN} option 12 for container shard-03-node-a ${NC}"   
    msg "${CYAN} option 13 for container shard-03-node-b ${NC}"     
    msg "${CYAN} option 14 for container shard-03-node-c ${NC}\n"  

    read -r -p "Selected option (1-14): " CHECK_RESP_CONTAINER

    case "$CHECK_RESP_CONTAINER" in
        1) function_pmm-admin_command "router-01" ;;
        2) function_pmm-admin_command "router-02" ;;
        3) function_pmm-admin_command "mongo-config-01" ;;
        4) function_pmm-admin_command "mongo-config-02" ;;
        5) function_pmm-admin_command "mongo-config-03" ;;
        6) function_pmm-admin_command "shard-01-node-a" ;;
        7) function_pmm-admin_command "shard-01-node-b" ;;
        8) function_pmm-admin_command "shard-01-node-c" ;;
        9) function_pmm-admin_command "shard-02-node-a" ;;
       10) function_pmm-admin_command "shard-02-node-b" ;;
       11) function_pmm-admin_command "shard-02-node-c" ;;
       12) function_pmm-admin_command "shard-03-node-a" ;;
       13) function_pmm-admin_command "shard-03-node-b" ;;
       14) function_pmm-admin_command "shard-03-node-c" ;;
       *)  msg "❌ Invalid input: '$CHECK_RESP_CONTAINER'. Please enter a number between 1 and 14." ;;
    esac
}
#######################################
# ++ function function_pmm-admin_command
#######################################
function function_pmm-admin_command {
  # $1 = container name 
  local CONTAINER_NAME="$1"
  local CHECK_RESP=''
  #
    while [ "$CHECK_RESP" != "6" ]; do
      msg "${CYAN}    option 1 - pmm-admin status within container: $CONTAINER_NAME${NC}"
      msg "${CYAN}    option 2 - pmm-admin inventory list nodes within container: $CONTAINER_NAME${NC}"
      msg "${CYAN}    option 3 - pmm-admin inventory list agents within container: $CONTAINER_NAME${NC}"
      msg "${CYAN}    option 4 - pmm-admin inventory list services within container: $CONTAINER_NAME${NC}"
      msg "${CYAN}    option 5 - pmm-admin inventory list --service-type=mongodb services within container: $CONTAINER_NAME${NC}"
      msg "${CYAN}    option 6 - exit this sub-menu ${NC}\n"
      #
      read -r -p "Selected option (1, 2, 3, 4, 5 or 6): " CHECK_RESP
      # 
      if [ "$CHECK_RESP" = "1" ]; then
        msg "executing ==> docker exec $CONTAINER_NAME pmm-admin status"
        set -o xtrace
        docker exec "$CONTAINER_NAME" bash -c "echo; hostname -s; hostname -i ; echo; pmm-admin status"
        set +o xtrace
      elif [ "$CHECK_RESP" = "2" ]; then
        msg "executing ==> docker exec $CONTAINER_NAME pmm-admin inventory list nodes"
        docker exec "$CONTAINER_NAME" bash -c 'echo; hostname -s; hostname -i ; echo; pmm-admin inventory list nodes'
      elif [ "$CHECK_RESP" = "3" ]; then
        msg "executing ==> docker exec $CONTAINER_NAME pmm-admin inventory list agents"
        docker exec "$CONTAINER_NAME" bash -c 'echo; hostname -s; hostname -i ; echo;pmm-admin inventory list agents'     
      elif [ "$CHECK_RESP" = "4" ]; then
        msg "executing ==> docker exec $CONTAINER_NAME pmm-admin inventory list services"
        docker exec "$CONTAINER_NAME" bash -c 'echo; hostname -s; hostname -i ; echo;pmm-admin inventory list services'    
      elif [ "$CHECK_RESP" = "5" ]; then
        msg "executing ==> docker exec $CONTAINER_NAME pmm-admin inventory list --service-type=mongodb services"
        docker exec "$CONTAINER_NAME" bash -c 'echo; hostname -s; hostname -i ; echo; pmm-admin inventory list services --service-type=mongodb'          
      elif [ "$CHECK_RESP" != "6" ]; then
        msg "Invalid input of $CHECK_RESP. Please enter 1, 2, ,3,4,5 or 6."
      fi
    done
}
#######################################
# ++ function function_start_pbm
#######################################
function function_start_pbm {

  msg "\nTriggering the action to start the pbm-agent inside the different docker containers ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
    msg "\n${CYAN} Answer was not Y , skipping function_start_pbm${NC}\n"
  else  
    #
    # the pbm-agent does not work with the mongos service being the main mongodb service running within that container , so we should not try tos start it 
    #
    #function_start-pbm-client_within_mongodb_containers "router-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "ROUTER"
    #
    # the pbm-agent does not work with the mongos service being the main mongodb service running within that container , so we should not try tos start it 
    #
    #function_start-pbm-client_within_mongodb_containers "router-02" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "ROUTER"
    #
    function_start-pbm-client_within_mongodb_containers "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "CONFIG"
    function_start-pbm-client_within_mongodb_containers "mongo-config-02" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "CONFIG"
    function_start-pbm-client_within_mongodb_containers "mongo-config-03" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "CONFIG"
    function_start-pbm-client_within_mongodb_containers "shard-01-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-01-node-b" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-01-node-c" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-02-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-02-node-b" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-02-node-c" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-03-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-03-node-b" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
    function_start-pbm-client_within_mongodb_containers "shard-03-node-c" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "SHARD"
  fi 
}
#######################################
# ++ function function_re-start_pbm
#######################################
function function_re-start_pbm {
  #
  msg "\nTriggering the action to re-start the pbm-agent inside the different docker containers ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
     msg "\n${CYAN} Skipping function_re-start_pbm${NC}\n"
  else 
    #
    # the pbm-agent does not work with the mongos service being the main mongodb service running within that container , so we should not try tos start it 
    #
    #function_re-start-pbm-client_within_mongodb_containers "router-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "ROUTER"
    #
    # the pbm-agent does not work with the mongos service being the main mongodb service running within that container , so we should not try tos start it 
    #
    #function_re-start-pbm-client_within_mongodb_containers "router-02" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "ROUTER"
    #
    function_pkill-pbm-client_within_mongodb_containers "mongo-config-01" 
    function_pkill-pbm-client_within_mongodb_containers "mongo-config-02" 
    function_pkill-pbm-client_within_mongodb_containers "mongo-config-03" 
    function_pkill-pbm-client_within_mongodb_containers "shard-01-node-a" 
    function_pkill-pbm-client_within_mongodb_containers "shard-01-node-b" 
    function_pkill-pbm-client_within_mongodb_containers "shard-01-node-c" 
    function_pkill-pbm-client_within_mongodb_containers "shard-02-node-a"
    function_pkill-pbm-client_within_mongodb_containers "shard-02-node-b" 
    function_pkill-pbm-client_within_mongodb_containers "shard-02-node-c" 
    function_pkill-pbm-client_within_mongodb_containers "shard-03-node-a" 
    function_pkill-pbm-client_within_mongodb_containers "shard-03-node-b" 
    function_pkill-pbm-client_within_mongodb_containers "shard-03-node-c" 
    #
    #function_pmm-client-agent 
    check_cashed_function_pmm-client-agent
    function_start_pbm
  fi 
}

#######################################
# ++ function function_check_pmm-client_status
#######################################
function function_check_pmm-client_status {
  #
  msg "\nTriggering the action to start looking at the pmm-client (pmm-agent) inside the different docker containers ..." 
  read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "N" ] ; then
     msg "\n${CYAN} Skipping the function_check_pmm-client_status function ${NC}\n"
  else   
     #
     function_check_pmm-client_within_container "router-01" 
     function_check_pmm-client_within_container "router-02" 
     function_check_pmm-client_within_container "mongo-config-01" 
     function_check_pmm-client_within_container "mongo-config-02" 
     function_check_pmm-client_within_container "mongo-config-03" 
     function_check_pmm-client_within_container "shard-01-node-a" 
     function_check_pmm-client_within_container "shard-01-node-b" 
     function_check_pmm-client_within_container "shard-01-node-c" 
     function_check_pmm-client_within_container "shard-02-node-a" 
     function_check_pmm-client_within_container "shard-02-node-b"  
     function_check_pmm-client_within_container "shard-02-node-c"   
     function_check_pmm-client_within_container "shard-03-node-a" 
     function_check_pmm-client_within_container "shard-03-node-b" 
     function_check_pmm-client_within_container "shard-03-node-c"  
  fi
}
#######################################
# ++ function start-pbm-client_within_mongodb_containers 
#######################################
function function_start-pbm-client_within_mongodb_containers {
     # $1 = container name 
     # $2 = PBM_MONGODB_URI_VALUE
     # $3 = special flag
      local CONTAINER_NAME="$1"
      local PBM_MONGODB_URI_VALUE="$2"
      #local SPECIAL_FLAG="$3"
      #
      msg "\n${ORANGE}${BOLD} start pbm client within the container $CONTAINER_NAME ${NC}\n"
      #
      #echo "storage:" > $SOLUTION_HOME_DIR/scripts/pbm-config.yaml 
      #echo "  type: filesystem" >> $SOLUTION_HOME_DIR/scripts/pbm-config.yaml
      #echo "  filesystem:" >> $SOLUTION_HOME_DIR/scripts/pbm-config.yaml
      #echo "     path: /backup/default" >> $SOLUTION_HOME_DIR/scripts/pbm-config.yaml
      #
      #
      #mkdir "$SOLUTION_HOME_DIR"/backup/default
      #chown mongodb:mongodb "$SOLUTION_HOME_DIR"/backup/default
      #chmod 750 "$SOLUTION_HOME_DIR"/backup/default
      #
      tee $SOLUTION_HOME_DIR/scripts/pbm-config.yaml 1> /dev/null <<EOF
storage:
  type: filesystem
  filesystem:
     path: /backup/default  
EOF
      #
      #
       docker cp $SOLUTION_HOME_DIR/scripts/pbm-config.yaml "$CONTAINER_NAME:"/pbm-config.yaml
       #
       docker exec "$CONTAINER_NAME" pbm config --file ./pbm-config.yaml --mongodb-uri="$PBM_MONGODB_URI_VALUE"
       #
       #docker exec "$CONTAINER_NAME" mkdir -p /log/pbm/"$CONTAINER_NAME"/
       #
       #
       if [ -f "$SOLUTION_HOME_DIR/scripts/start_pbm_file.sh"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/scripts/start_pbm_file.sh, deleting it"
          rm -f "$SOLUTION_HOME_DIR/scripts/start_pbm_file.sh" 
      fi    
      msg "\ncreating the file $SOLUTION_HOME_DIR/scripts/start_pmm_file.sh ...\n"
      #
      tee $SOLUTION_HOME_DIR/scripts/start_pbm_file.sh > /dev/null <<EOF
#!/bin/bash
nohup pbm-agent --mongodb-uri $PBM_MONGODB_URI_VALUE > /log/pbm-agent-$CONTAINER_NAME.log 2>&1 &
EOF
      #
       docker cp $SOLUTION_HOME_DIR/scripts/start_pbm_file.sh "$CONTAINER_NAME:"/start_pbm_file.sh
       rm $SOLUTION_HOME_DIR/scripts/start_pbm_file.sh
       set -o xtrace
       docker exec "$CONTAINER_NAME" bash -c "chmod +x start_pbm_file.sh"
       docker exec "$CONTAINER_NAME" bash -c "/start_pbm_file.sh"
       set +o xtrace
      #
      # ---------------
      #
      if [ -f "$SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/kill_pbm_process_file.sh, deleting it"
          rm -f "$SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh" 
      fi 
      msg "\nCreating the file $SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh ... \n"
      #
      tee $SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh > /dev/null <<EOF
#!/bin/bash
#
pkill -f pbm-agent
EOF
      #
      docker cp $SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh "$CONTAINER_NAME:"/kill_pbm_process_file.sh
      rm $SOLUTION_HOME_DIR/scripts/kill_pbm_process_file.sh
      docker exec -t "$CONTAINER_NAME" bash -c "chmod +x kill_pbm_process_file.sh"
      #
}
#######################################
# ++ function re-start-pbm-client_within_mongodb_containers 
#######################################
function function_pkill-pbm-client_within_mongodb_containers {
    # $1 = container name  
    # 
    #set -o xtrace
    local CONTAINER_NAME="$1"
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    msg "${ORANGE}${BOLD} pkill the pbm-agent process within the $CONTAINER_NAME container ${NC}\n"
    docker exec -t "$CONTAINER_NAME" bash -c "/kill_pbm_process_file.sh"
#
#set +o xtrace
}
#######################################
# ++ function function_create_test-data_shard  
#######################################
function function_create_test-data_shard  {
      # $1 = container name 
      local CONTAINER_NAME="$1"
      #
      msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
      #
      if [ -f "$SOLUTION_HOME_DIR/scripts/temp_create_dummydata.js"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/scripts/temp_create_dummydata.js, deleting it"
          rm -f "$SOLUTION_HOME_DIR/scripts/temp_create_dummydata.js" 
      fi 
      msg "\nCreating the file $SOLUTION_HOME_DIR/scripts/temp_create_dummydata1.js ...\n"
      #
      tee $SOLUTION_HOME_DIR/scripts/temp_create_dummydata.js 1> /dev/null <<EOF
use dummydata1;
sh.enableSharding("dummydata1");
sh.shardCollection("dummydata1.users", {"user_id": "hashed"});
for (var i = 1; i <= 30000; i++) { 
    db.users.insert({ user_id: "user" + i, created_at: new Date() });
}
db.users.getShardDistribution();
use dummydata2;
sh.enableSharding("dummydata2");
sh.shardCollection("dummydata2.users", {"user_id": "hashed"});
for (var i = 1; i <= 30; i++) { 
    db.users.insert({ user_id: "user" + i, created_at: new Date() });
}
db.users.getShardDistribution();
use dummydata3;
sh.enableSharding("dummydata3");
sh.shardCollection("dummydata3.users", {"user_id": "hashed"});
for (var i = 1; i <= 30; i++) { 
    db.users.insert({ user_id: "user" + i, created_at: new Date() });
}
db.users.getShardDistribution();
exit;
EOF
      #
      #
      docker exec -t "$CONTAINER_NAME" bash -c "mongosh -u \"$PERCONA_MONGODB_PMM_USERNAME\" -p \"$PERCONA_MONGODB_PMM_PASSWORD\" < /scripts/temp_create_dummydata.js"
      #
}
#######################################
# ++ function function_delete_dummydata_DB_collection
#######################################
function function_delete_dummydata_DB_collection {
      # $1 = container name 
      local CONTAINER_NAME="$1"
      #
     msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    #
      if [ -f "$SOLUTION_HOME_DIR/scripts/temp_delete_dummydata_collection.js"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/temp_delete_dummydata_collection.js, deleting it"
          rm -f "$SOLUTION_HOME_DIR/scripts/temp_delete_dummydata_collection.js" 
      fi 
      msg "\nCreating the file $SOLUTION_HOME_DIR/scripts/temp_delete_dummydata_collection.js\n"
      #
      tee $SOLUTION_HOME_DIR/scripts/temp_delete_dummydata_collection.js 1> /dev/null <<EOF
use dummydata1;
db.getCollectionNames();
db.users.drop();
db.getCollectionNames();
use dummydata2;
db.getCollectionNames();
db.users.drop();
db.getCollectionNames();
use dummydata3;
db.getCollectionNames();
db.users.drop();
db.getCollectionNames();
exit;
EOF
    #
    docker exec -t "$CONTAINER_NAME" bash -c "mongosh -u \"$PERCONA_MONGODB_PMM_USERNAME\" -p \"$PERCONA_MONGODB_PMM_PASSWORD\" < /scripts/temp_delete_dummydata_collection.js"
    #  
}
#######################################
# ++ function function_get_mongodb_version
#######################################
function function_get_mongodb_version {
     # $1 = container name 
     local CONTAINER_NAME="$1"
     #
     msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
     #
     docker exec "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'db.version()'
}
#######################################
# ++ function function_get_dbisMaster
#######################################
function function_get_dbisMaster {
      # $1 = container name 
      local CONTAINER_NAME="$1"
      #
      msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
      #
      docker exec -t "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'db.isMaster()'
}
#######################################
# ++ function function_get_shard
#######################################
function function_getShardDistribution {
      # $1 = container name 
      local CONTAINER_NAME="$1"
      #
     msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
      #
       if [ -f "$SOLUTION_HOME_DIR/scripts/temp_read_dummydata.js"  ] ; then
          msg "\nFound this file $SOLUTION_HOME_DIR/scripts/temp_read_dummydata.js. deleting it"
          rm -f "$SOLUTION_HOME_DIR/scripts/temp_read_dummydata.js" 
      fi  
      msg "\ncreating file $SOLUTION_HOME_DIR/scripts/temp_read_dummydata.js ...\n"
      #
      tee $SOLUTION_HOME_DIR/scripts/temp_read_dummydata.js 1> /dev/null <<EOF
use dummydata1;
db.users.getShardDistribution();
use dummydata2;
db.users.getShardDistribution();
use dummydata3;
db.users.getShardDistribution();
exit;
EOF
       #
       docker exec -t "$CONTAINER_NAME" bash -c "mongosh -u \"$PERCONA_MONGODB_PMM_USERNAME\" -p \"$PERCONA_MONGODB_PMM_PASSWORD\" < /scripts/temp_read_dummydata.js"
       #
}
#######################################
# ++ function function_get_mongodb_adm_info
#######################################
function function_get_mongodb_adm_info {
   #
   msg "\n${CYAN} We need to collect the ${ORANGE} main ADM mongodb username and password ${NC}${CYAN}for the mongodb instance ${NC}"
   msg "${CYAN} Consult with ${ORANGE}your mongodb administrator resource${NC}${CYAN} for this information ${NC}"
   msg "${CYAN} required latter in this script ${NC}"
   #
   msg  "\nMain MongoDB instance ADMIN (root) username to be used  ?"
   read -r -p "Please enter your response " RESP_MONGODB_ADM_USERNAME

  if [ "$RESP_MONGODB_ADM_USERNAME" =  "" ] ; then
    die "${RED} main mongodb instance administrator username value can not be left empty ${NC}"
  else
    MONGODB_ADM_USER=$RESP_MONGODB_ADM_USERNAME
  fi 
  # 
  msg "\nMain MongoDB instance ADM password ?"
  msg "${BOLD}Password characters will not be displayed${NC}"
  read -r -s -p " Please enter your response  " RESP_MONGODB_ADM_PASSW

  if [ "$RESP_MONGODB_ADM_PASSW" = "" ] ; then
    die "${RED} main mongodb instance administrator password value can not be left empty ${NC}"
  else
    MONGODB_ADM_PASSWORD=$RESP_MONGODB_ADM_PASSW
  fi 
}
#######################################
# ++ function check_cashed_function_get_mongodb_adm_info
#######################################
function check_cashed_function_get_mongodb_adm_info {
    #
    # 
    #
    if [ "$MONGODB_ADM_USER" = "" ]; then
         function_get_mongodb_adm_info
    else 
        msg    
        msg "      Currently (information temporary cached within this script only) MongoDB PMM Username: ${BOLD}$MONGODB_ADM_USER${NC}"
        msg "      Currently (information temporary cached within this script only) MongoDB PMM Password: ${BOLD}$MONGODB_ADM_PASSWORD${NC}"
        msg "\nIs the above information correct ?" 
        read -r -p "Please enter your response (Y/N) [ default: Y ] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "N" ] ; then
          function_get_mongodb_adm_info
       else
          msg "\nLet's continue ...\n"
      fi    
    fi
}
#######################################
# ++ function function_disable_pmnm-client_automatic_start
#######################################
function function_disable_pmnm-client_automatic_start {
#
msg "\nConfirm disabling the script start_pmm_file.sh inside the containers ..." 
read -r -p "Please enter your response (Y/N) default: [N] " RESP

RESP=${RESP^^} # convert to upper case 
if [ "$RESP" = "Y" ] ; then
     #
     function_disable_pmm-client_automatic_action "router-01" 
     function_disable_pmm-client_automatic_action "router-02" 
     function_disable_pmm-client_automatic_action "mongo-config-01" 
     function_disable_pmm_client_automatic_action "mongo-config-02" 
     function_disable_pmm-client_automatic_action "mongo-config-03" 
     function_disable_pmm-client_automatic_action "shard-01-node-a" 
     function_disable_pmm-client_automatic_action "shard-01-node-b" 
     function_disable_pmm-client_automatic_action "shard-01-node-c" 
     function_disable_pmm-client_automatic_action "shard-02-node-a" 
     function_disable_pmm-client_automatic_action "shard-02-node-b"  
     function_disable_pmm-client_automatic_action "shard-02-node-c"   
     function_disable_pmm-client_automatic_action "shard-03-node-a" 
     function_disable_pmm-client_automatic_action "shard-03-node-b" 
     function_disable_pmm-client_automatic_action "shard-03-node-c"  
     msg "\n${CYAN}All the MongoDB containers will need to restarted for this change to take effect ${NC}\n"
else
    msg "\n${CYAN} Skipping the function_disable_pmm-client_automatic_start function ${NC}\n"
fi
}
#######################################
# ++ function function_disable_pmm-client_automatic_action
#######################################
function function_disable_pmm-client_automatic_action {
    # $1 = container name 
    local CONTAINER_NAME="$1"
    #
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    echo "# Percona PMM is empty for now" > $SOLUTION_HOME_DIR/tmp/start_pmm_file.sh
    echo "echo file is empty > start_pmm_file.txt" >> $SOLUTION_HOME_DIR/tmp/start_pmm_file.sh
    docker cp $SOLUTION_HOME_DIR/tmp/start_pmm_file.sh "$CONTAINER_NAME:"/start_pmm_file.sh
}
#######################################
# ++ function function_disable_pbnm-client_automatic_start
#######################################
function function_disable_pbnm-client_automatic_start {
    #
    msg "\nConfirm disabling the script function_disable_pmnm-client_automatic_start ..."
    read -r -p "Please enter your response (Y/N) default: [N] " RESP

RESP=${RESP^^} # convert to upper case 
if [ "$RESP" = "Y" ] ; then
     #
     #
     function_disable_pbm-client_automatic_action "router-01" 
     function_disable_pbm-client_automatic_action "router-02" 
     function_disable_pbm-client_automatic_action "mongo-config-01" 
     function_disable_pbm-client_automatic_action "mongo-config-02" 
     function_disable_pbm_client_automatic_action "mongo-config-03" 
     function_disable_pbm-client_automatic_action "shard-01-node-a" 
     function_disable_pbm-client_automatic_action "shard-01-node-b" 
     function_disable_pbm-client_automatic_action "shard-01-node-c" 
     function_disable_pbm-client_automatic_action "shard-02-node-a" 
     function_disable_pbm-client_automatic_action "shard-02-node-b"  
     function_disable_pbm-client_automatic_action "shard-02-node-c"   
     function_disable_pbm-client_automatic_action "shard-03-node-a" 
     function_disable_pbm-client_automatic_action "shard-03-node-b" 
     function_disable_pbm-client_automatic_action "shard-03-node-c"  
     msg "\n${CYAN}All the MongoDB containers will need to restarted for this change to take effect  ${NC}\n"
else
    msg "\n${CYAN} Answer was not Y, skipping function_disable_pbm-client_automatic_start ${NC}\n"
fi
}
#######################################
# ++ function function_disable_pbm-client_automatic_action
#######################################
function function_disable_pbm-client_automatic_action {
    # $1 = container name 
    local CONTAINER_NAME="$1"
    #
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    echo "# Percona PBM is empty for now" > $SOLUTION_HOME_DIR/tmp/start_pbm_file.sh
    echo "echo file is empty > start_pbm_file.txt" >> $SOLUTION_HOME_DIR/tmp/start_pbm_file.sh
    docker cp $SOLUTION_HOME_DIR/tmp/start_pbm_file.sh "$CONTAINER_NAME:"/start_pbm_file.sh
}
#######################################
# ++ function function_check_health_of_cluster
#######################################
function function_check_health_of_cluster {
    # $1 = router container name where mongos is running on
    local CONTAINER_NAME="$1"
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    #
    docker exec -t "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'rs.status()'
    docker exec -t "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'db.serverStatus()'
}
#######################################
# ++ function function_get_stats_cluster
#######################################
function function_get_stats_cluster {
    # $1 = router container name where mongos is running on
    local CONTAINER_NAME="$1"
    #
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    docker exec -t "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'db.serverStatus()'
}
#######################################
# ++ function function_show_db
#######################################
function function_show_db {
    # $1 = router container name where mongos is running on
    local CONTAINER_NAME="$1"
    #
    msg "\n${ORANGE}Container: $CONTAINER_NAME ${NC}\n"
    docker exec -t "$CONTAINER_NAME" mongosh -u "$PERCONA_MONGODB_PMM_USERNAME" -p "$PERCONA_MONGODB_PMM_PASSWORD" --eval 'show dbs;'
}
#######################################
# ++  function function_pbm_restore_backup
#######################################
function function_pbm_restore_backup {
    msg "\n${ORANGE}${BOLD} function_pbm_restore_backup ${NC}\n"
    # $1 = PBM_MONGODB_URI_VALUE
    local CONTAINER_PERFORMING_RESTORE="$1"
    #
    msg "\n${CYAN}To restore a Percona Backup for MongoDB (PBM) backup of a shard MongoDB cluster through the Percona Monitoring and Management (PMM) GUI,
you'll need to use the PBM CLI for the actual restore process, as PMM handles backups but not the restore process end-to-end.

Here's a breakdown of the process:

1. Backups in PMM:
PMM supports creating backups of sharded MongoDB clusters using PBM.
You can manage backups (create, list, delete) through the PMM UI.
PMM can be configured to monitor MongoDB, and you can manage backups for MongoDB in PMM.
PMM handles the backup process end-to-end, but the restore process requires manual intervention using the PBM CLI.

2. Restoring with PBM CLI:
List Backups: Use the pbm list command to see the available backups.
Restore: Use the pbm restore <backup_name> command to restore a backup.
Sharded Environment: You can only restore a sharded backup into another sharded environment (either your existing cluster or a new one).
New Environment: If restoring into a new environment, refer to the Percona Backup for MongoDB documentation for specific instructions.
${NC}\n"
    #
	  read -r -p"[Hit Return] to continue ..." DUMMY_RESP
    echo "$DUMMY_RESP" > /dev/null #"the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   

    msg "\n${ORANGE}${BOLD} Making some changes in MongoDB to prepare for the restore action ${NC}\n"

    #
    # set -o xtrace
    function_pbm-client_command "$CONTAINER_PERFORMING_RESTORE" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "status"
    docker exec -t "$CONTAINER_PERFORMING_RESTORE" ls -l /backup
    function_pbm-client_command "$CONTAINER_PERFORMING_RESTORE" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "config"
    function_pbm-client_command "$CONTAINER_PERFORMING_RESTORE" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "list"

    # Ask for backup file name
    echo # need a blank line here 
    read -r -p "Please enter your response for the file name: " BACKUP_FILE
    if [ -z "$BACKUP_FILE" ]; then
        die "${ORANGE}${BOLD} PHYSICAL_BACKUP_FILE cannot be blank ${NC}"
    fi
    # Ask for the type of restore
    echo # need a blank line here 
    read -r -p "Is this a logical or physical PBM restore? (1 = logical, 2 = physical): " WHAT_KIND_OF_PBM_RESTORE
    if [ -z "$WHAT_KIND_OF_PBM_RESTORE" ]; then
        die "${ORANGE}${BOLD} Kind or restore cannot be blank ${NC}"
    fi
    case "$WHAT_KIND_OF_PBM_RESTORE" in
    1)
        echo "Performing a logical restore..."
        KIND_OF_PBM_RESTORE="logical"
        ;;
    2)
        echo "Performing a physical restore..."
        KIND_OF_PBM_RESTORE="physical"
        ;;
    *)
        echo "Invalid value entered: for WHAT_KIND_OF_PBM_RESTORE (valid values are 1 or 2) and this was entered: $WHAT_KIND_OF_PBM_RESTORE"
        return 1
        ;;
    esac
    #
    if [ "$KIND_OF_PBM_RESTORE" = "physical" ]; then
       #
       #  To confirm no I/O hists the database before starting the restore 
       # 

       msg "\n${ORANGE}Stating the pdbm restore activities against a pbm physical backup ${NC}"
       msg "${ORANGE}To confirm no I/O interferes with the restore process , we need to stop the 2 MongoDB (mongos) router containers  ${NC}\n"

       msg "\nOk to continue  ?"
       read -r -p "Please enter your response (Y/N) [ default: N] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "Y" ] ; then 
          docker stop router-01
          docker stop router-02
       else 
          msg "\nSkipping triggering stopping the mongos (router) containers\n" 
       fi 
       msg "\nBefore continuing , from a second ssh session  off this system, perform a tail -f logs/pbm*.log to see the progress of the restore\n"
       msg "\nOk to trigger the pbm restore process against this file:  $BACKUP_FILE that was create by pbm physical backup"
       read -r -p "Please enter your response (Y/N) [ default: N] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "Y" ] ; then 
          set -o xtrace
          docker exec -t "$CONTAINER_PERFORMING_RESTORE" pbm restore "$BACKUP_FILE" --mongodb-uri "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
          set +o xtrace
          msg "\n${ORANGE}${BOLD}The restore action is ASYNC, so we need to check the status and logs  ${NC}"
          msg "\n${ORANGE}${BOLD} Keep monitoring the pbm logs files, and given we have trigger a physical restore  ${NC}"
          msg "${ORANGE}${BOLD} at some point all the MongoDB process will we stopped, and you will ${NC}"
          msg "${ORANGE}${BOLD} need to restart all the MongoDb containers once the logs confirm the restore was successfully${NC}"
        else 
          msg "\nSkipping triggering the pbm restore activities ...\n" 
       fi    
      
    fi
    #
    if [ "$KIND_OF_PBM_RESTORE" = "logical" ]; then
       #
       #  To confirm no I/O hists the database before starting the restore 
       # 

       msg "\n${ORANGE}Stating the pdbm restore activities against a pbm logical backup ${NC}"
       msg "${ORANGE}To confirm no I/O interferes with the restore process , we need to stop the 2 MongoDB (mongos) router containers  ${NC}\n"

       msg "\nOk to continue  ?"
       read -r -p "Please enter your response (Y/N) [ default: N] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "Y" ] ; then 
          docker stop router-01
          docker stop router-02
       else 
          msg "\nSkipping triggering stopping the mongos (router) containers\n" 
       fi    
       msg "\nBefore continuing , from a second ssh session  off this system, perform a tail -f logs/pbm*.log to see the progress of the restore\n"
       msg "\nOk to trigger the pbm restore process against this file:  $BACKUP_FILE that was create by pbm logical backup"
       read -r -p "Please enter your response (Y/N) [ default: N] " RESP

       RESP=${RESP^^} # convert to upper case 
       if [ "$RESP" = "Y" ] ; then 
          set -o xtrace
          docker exec -t "$CONTAINER_PERFORMING_RESTORE" pbm restore "$BACKUP_FILE" --mongodb-uri "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
          set +o xtrace
          msg "${ORANGE}${BOLD} restore action still going , we need to check the status and logs  ${NC}"
          msg "${ORANGE}${BOLD} Once from the logs , it appears the restore completed successfully, start the mongos (router-01 & router-02 ) containers  ${NC}"
        else 
          msg "\nSkipping triggering the pbm restore activities ...\n" 
       fi    
    fi  
}
#######################################
# ++ function  function_read_dummy_data 
#######################################
function  function_read_dummy_data {
    # $1 = router container name where mongos is running on
    local CONTAINER_NAME_ROUTER="$1"

    msg "\n${ORANGE}${BOLD}  function_read_dummy_data${NC}\n"

    msg "\nLet's go see if the database and collections are all there after ?"
    read -r -p "Please enter your response (Y/N) [ default: Y] " RESP

    RESP=${RESP^^} # convert to upper case 
    if [ "$RESP" = "N" ]; then
        msg "\nSkipping this section ...  Let's go see if the database and collection are there after the backup\n"
    else
        msg "\nFound this file $SOLUTION_HOME_DIR/scripts/temp_restore_router_action_3.js. deleting it"
        rm -f "$SOLUTION_HOME_DIR/scripts/temp_restore_router_action_3.js" 
        msg "\nCreating file $SOLUTION_HOME_DIR/scripts/temp_restore_router_action_3.js...\n"
        #
        tee $SOLUTION_HOME_DIR/scripts/temp_restore_router_action_3.js 1> /dev/null <<EOF
use dummydata1;
db.users.find().limit(10);
use dummydata2;
db.users.find().limit(3);
use dummydata3;
db.users.find().limit(3);
exit;
EOF
        #
        docker exec -t "$CONTAINER_NAME_ROUTER"  bash -c "mongosh -u \"$PERCONA_MONGODB_PMM_USERNAME\" -p \"$PERCONA_MONGODB_PMM_PASSWORD\" < /scripts/temp_restore_router_action_3.js"
    fi
}
#######################################
# ++ function function_connect_to_container_bash
#######################################
function function_connect_to_container_bash {
    # $1 = router container name where mongos is running on
    # $2 = PBM_MONGODB_URI_VALUE
    local CONTAINER_NAME="$1"
    local PBM_MONGODB_URI_VALUE="$2"
    docker exec -it "$CONTAINER_NAME" bash -c "export PBM_MONGODB_URI=\"$PBM_MONGODB_URI_VALUE\"; echo; echo; echo -e '${ORANGE}now in container $CONTAINER_NAME ${NC}'; bash"
}
#######################################
# ++ function add-PERCONA-pmm-client-mongodb_user_roles
#######################################
function function_add-PERCONA-pmm-client-mongodb_user_roles {
        #  
        msg "\n$ORANGE}${BOLD} Now in the function_add-PERCONA-pmm-client-mongodb_user_roles area ${NC}\n"
        #
        if [ -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_role_1_configuration.js"  ] ; then
              msg "\nFound this file $SOLUTION_HOME_DIR/scripts/percona_mongodb_role_1_configuration.js, deleting it"
              rm -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_role_1_configuration.js" 
        fi
        msg "\nCreating file $SOLUTION_HOME_DIR/scripts/percona_mongodb_role_1_configuration.js ...\n"
        #
        tee /$SOLUTION_HOME_DIR/scripts/percona_mongodb_role_1_configuration.js 1> /dev/null <<EOF
use admin
db.getSiblingDB('admin').createRole({
   'role': 'explainRole',
    'privileges': [
      {
         'resource': { 'db': '', 'collection': '' },
         'actions': [ 'dbHash', 'find', 'listIndexes', 'listCollections', 'collStats', 'dbStats', 'indexStats' ]
      },
      {
         'resource': { 'db': '', 'collection': 'system.version' },
         'actions': [ 'find' ]
      },
      {
         'resource': { 'db': '', 'collection': 'system.profile' },
         'actions': [ 'dbStats', 'collStats', 'indexStats' ]
      }
   ],
   'roles': []
});
exit;
EOF
        #
        if [ -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_role_2_configuration.js"  ] ; then
              msg "\nFound this file $SOLUTION_HOME_DIR/scripts/percona_mongodb_role_2_configuration.js, deleting it"
              rm -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_role_2_configuration.js" 
        fi
        msg "\nCreating file $SOLUTION_HOME_DIR/scripts/percona_mongodb_role_2_configuration.js...\n"
        #
        tee $SOLUTION_HOME_DIR/scripts/percona_mongodb_role_2_configuration.js 1> /dev/null <<EOF
use admin ;
db.getSiblingDB("admin").createRole({
    "role": "pbmAnyAction",
    "privileges": [
      {
        "resource": { "anyResource": true  },
        "actions": [ "anyAction" ]
      }
    ],
    "roles": []
});
exit;
EOF
        #
        if [ -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js "  ] ; then
              msg "\nFound this file $SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js , deleting it"
              rm -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js" 
        fi
       msg "\nCreating file $SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js ...\n"
        #
        tee $SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js 1> /dev/null <<EOF
use admin ;
db.getSiblingDB("admin").createUser({
    "user": "${PERCONA_MONGODB_PMM_USERNAME}",
    "pwd": "${PERCONA_MONGODB_PMM_PASSWORD}",
    "roles": [
        { "db" : "admin", "role": "explainRole" },
        { "db" : "local", "role": "read" },
        { "db" : "admin", "role" : "readWrite" },
        { "db" : "admin", "role" : "backup" },
        { "db" : "admin", "role" : "clusterMonitor" },
        { "db" : "admin", "role" : "restore" },
        { "db" : "admin", "role" : "pbmAnyAction" }
    ]
});
exit;
EOF
        #
        # Action are for this function
        #
        msg "\n${CYAN}==> mongo-config-01 <== percona_mongodb_role_1_configuration.js ${NC}\n"
        docker exec -t mongo-config-01 bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_1_configuration.js"
	      wait_with_message  2 ""

        msg "\n${CYAN}==> shard-01-node-a<== percona_mongodb_role_1_configuration.js ${NC}\n"
        docker exec -t shard-01-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_1_configuration.js"
        wait_with_message  2 ""
  
        msg "\n${CYAN}==> shard-02-node-a <== percona_mongodb_role_1_configuration.js ${NC}\n"
        docker exec -t shard-02-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_1_configuration.js"
        wait_with_message  2 ""
   
      
        msg "\n${CYAN}==> shard-03-node-a <== percona_mongodb_role_1_configuration.js ${NC}\n"
        docker exec -t shard-03-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_1_configuration.js"
        wait_with_message  2 ""
       #
       #
       #
        msg "\n${CYAN}==> router-01 <== percona_mongodb_role_2_configuration.js ${NC}\n"
        docker exec -it router-01 bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_2_configuration.js"
        wait_with_message  2 ""
   
        msg "\n${CYAN}==> shard-01-node-a  <== percona_mongodb_role_2_configuration.js ${NC}\n"
        docker exec -it shard-01-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_2_configuration.js"
       wait_with_message  2 ""
    
        msg "\n${CYAN}==> shard-02-node-a  <== percona_mongodb_role_2_configuration.js ${NC}\n"
        docker exec -it shard-02-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_2_configuration.js"
        wait_with_message  2 ""
    
        msg "\n${CYAN}==> shard-03-node-a  <== percona_mongodb_role_2_configuration.js ${NC}\n"
        docker exec -it shard-03-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_role_2_configuration.js"
        wait_with_message  2 ""
       #
       #
       #
        msg "\n${CYAN}==> router-01 <== percona_mongodb_user_configuration.js\n"
        docker exec -it router-01 bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_user_configuration.js"
        wait_with_message  2 ""
  
        msg "\n${CYAN}==> shard-01-node-a  <== percona_mongodb_user_configuration.js ${NC}\n"
        docker exec -it shard-01-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_user_configuration.js"
        wait_with_message  2 ""

        msg "\n${CYAN}==> shard-02-node-a  <== percona_mongodb_user_configuration.js ${NC}\n"
        docker exec -it shard-02-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_user_configuration.js"
        wait_with_message  2 ""
  
        msg "\n${CYAN}==> shard-03-node-a  <== percona_mongodb_user_configuration.js ${NC}\n"
        docker exec -it shard-03-node-a bash -c "mongosh -u \"$MONGODB_ADM_USER\" -p \"$MONGODB_ADM_PASSWORD\" < /scripts/percona_mongodb_user_configuration.js"
        #
        msg "\n${CYAN}Deleting the file $SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js ${NC}\n"
        rm -f "$SOLUTION_HOME_DIR/scripts/percona_mongodb_user_configuration.js"  # removing this file because it  has username & password information 
}
#######################################
# ++ function function_recreate_pbm_config_file
#######################################
function function_recreate_pbm_config_file {
    # $1 = CONTAINER_NAME
    # $2 = FOLDER_TO_CHECK 
    local CONTAINER_NAME="$1"
    local FOLDER_TO_CHECK="$2"
    #
    msg "\nHere at the existing folder list under $FOLDER_TO_CHECK within $CONTAINER_NAME${NC}\n"
    docker exec -t "$CONTAINER_NAME" ls -htl "$FOLDER_TO_CHECK" | grep "^d"
    msg    
    msg "\nContent of /pbm-config.yaml\n"
    docker exec -t "$CONTAINER_NAME" cat ./pbm-config.yaml 

    msg "\nWhat is the sub-folder name "
    read -r -p "Please enter your response (e.g. mstools , mssql105, jfrog ... ), [ return to no changes ] " RESP_SUB_FOLDER

    NEW_FULL_PATH="${FOLDER_TO_CHECK}/${RESP_SUB_FOLDER}"

    msg  "\nThis is the new path: $NEW_FULL_PATH,  is this correct ?"
    read -r -p "Do you want to modify the file pbm-config.yaml? (Y/N) [default: N] " RESP
  
    RESP=${RESP^^} # Convert to uppercase
    if [ "$RESP" = "Y" ]; then
       msg "\nModifying the file /pbm-config.yaml\n"
       #
       tee /tmp/pbm-config.yaml > /dev/null <<EOF
storage:
  type: filesystem
  filesystem:
     path: $NEW_FULL_PATH
EOF
       #
       msg  "\nExecuting ==> pbm config --file ./pbm-config.yaml\n"
       set -o xtrace
       docker cp /tmp/pbm-config.yaml "$CONTAINER_NAME":/pbm-config.yaml
       docker exec -t "$CONTAINER_NAME" cat pbm-config.yaml
       docker exec -t "$CONTAINER_NAME" pbm config --file ./pbm-config.yaml --mongodb-uri="mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost/?authSource=admin" 
       set +o xtrace
       copy_pbm-config.yaml_to_remaining_containers
       #
    else
        echo # needing a blank line here 
        read -r -p "Do you want to reload the file /pbm-config.yaml to it's default default? (Y/N) [default: N] " RESP

       RESP=${RESP^^}
       if [ "$RESP" = "Y" ]; then
          tee /tmp/pbm-config.yaml > /dev/null <<EOF
storage:
  type: filesystem
  filesystem:
     path: /backup/default
EOF
         #
         msg "\nexecuting ==> pbm config --file ./pbm-config.yaml\n"
         set -o xtrace
         docker cp /tmp/pbm-config.yaml "$CONTAINER_NAME":/pbm-config.yaml
         docker exec -t "$CONTAINER_NAME"  pbm config --file ./pbm-config.yaml --mongodb-uri="mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost/?authSource=admin" 
         set +o xtrace
         copy_pbm-config.yaml_to_remaining_containers
      else
        # 
        msg "\nexecuting ==> pbm config to check it's current status\n"
        # 
        set -o xtrace
        docker exec -t "$CONTAINER_NAME" pbm config --mongodb-uri="mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost/?authSource=admin" 
        set +o xtrace
        #
        msg "\nSkipping modifying the file /pbm-config.yaml\n"
      fi
   fi
}
#######################################
# ++ function get_container_information
#######################################
function get_container_information {
     # 
     # $1 = CONTAINER_NAME
     local CONTAINER_NAME="$1"
     #
     IP_OF_CONTAINER=$(docker exec "${CONTAINER_NAME}"  hostname -i)
     CONTAINER_HOSTNAME=$(docker exec "${CONTAINER_NAME}"  hostname -s)
     TEMP_NAME=$(hostname -s)_${CONTAINER_NAME}

     msg "\n${ORANGE}Container information:  ${NC} "
     msg "          Container name: $CONTAINER_NAME , hostname inside the container: $CONTAINER_HOSTNAME, IP of the container:  $IP_OF_CONTAINER" 
     
}
#######################################
# ++ function copy_pbm-config.yaml_to_remaining_containers
#######################################
function copy_pbm-config.yaml_to_remaining_containers {
        #
        #
        set -o xtrace
        docker cp /tmp/pbm-config.yaml mongo-config-01:/pbm-config.yaml
        docker cp /tmp/pbm-config.yaml mongo-config-02:/pbm-config.yaml
        docker cp /tmp/pbm-config.yaml mongo-config-03:/pbm-config.yaml
        docker cp /tmp/pbm-config.yaml shard-01-node-a:/pbm-config.yaml   
        docker cp /tmp/pbm-config.yaml shard-01-node-b:/pbm-config.yaml
        docker cp /tmp/pbm-config.yaml shard-01-node-c:/pbm-config.yaml 
        docker cp /tmp/pbm-config.yaml shard-02-node-a:/pbm-config.yaml  
        docker cp /tmp/pbm-config.yaml shard-02-node-b:/pbm-config.yaml      
        docker cp /tmp/pbm-config.yaml shard-02-node-c:/pbm-config.yaml  
        docker cp /tmp/pbm-config.yaml shard-03-node-a:/pbm-config.yaml 
        docker cp /tmp/pbm-config.yaml shard-03-node-b:/pbm-config.yaml    
        docker cp /tmp/pbm-config.yaml shard-03-node-c:/pbm-config.yaml
        set +o xtrace

}
#######################################
# ++ function function_unregister_pmm_agent
#######################################
function function_unregister_pmm_agent {
   #
   msg "\nTriggering the action pmm-agent unregister --force  ..."
   read -r -p "Please enter your response (Y/N) [ default: N] " RESP

  RESP=${RESP^^} # convert to upper case 
  if [ "$RESP" = "Y" ] ; then
        #
        docker exec -t -u 0  router-01 pmm-admin unregister --force 
        docker exec -t -u 0  router-02 pmm-admin unregister --force 
        docker exec -t -u 0  mongo-config-01 pmm-admin unregister --force 
        docker exec -t -u 0  mongo-config-02 pmm-admin unregister --force 
        docker exec -t -u 0  mongo-config-03 pmm-admin unregister --force 
        docker exec -t -u 0  shard-01-node-a pmm-admin unregister --force 
        docker exec -t -u 0  shard-01-node-b pmm-admin unregister --force 
        docker exec -t -u 0  shard-01-node-c pmm-admin unregister --force  
        docker exec -t -u 0  shard-02-node-a pmm-admin unregister --force    
        docker exec -t -u 0  shard-02-node-b pmm-admin unregister --force       
        docker exec -t -u 0  shard-02-node-c pmm-admin unregister --force    
        docker exec -t -u 0  shard-03-node-a pmm-admin unregister --force    
        docker exec -t -u 0  shard-03-node-b pmm-admin unregister --force      
        docker exec -t -u 0  shard-03-node-c pmm-admin unregister --force   
  else  
    msg "\n${CYAN} Skipping function_unregister_pmm_agent ${NC}\n"
  fi   
}
#######################################
# ++ function help_menu_function
#######################################
function help_menu_function() {
     #
     msg "${BOLD}"
     #
     cat <<EOF
     option 1 - add PERCONA pmm user and roles within MongoDB 
     Adds a user with roles required by PMM and PBM
     To add a Percona Monitoring and Management (PMM) user in MongoDB with the required roles 
     for both PMM Agent and Percona Backup for MongoDB (PBM) to operate correctly

     option 2 - setup configure pmm-agent using pmm-agent --force option 
     Method  to configure the pmm-agent using the pmm-agent setup command
     Forces setup of pmm-agent, useful for reinitializing

     option 3 - setup configure pmm-admin config (preferred option) with the --force option 
     Method  to configure the pmm-agent using the pmm-admin config command
     Sets up pmm-admin config with force override

     option 4 - start pmm-agent 
     start the pmm-agent within each of the MongoDB containers

     option 5 - register mongodb services
     Uses pmm-admin to add MongoDB service for monitoring in order to start monitoring MongoDB instance

     option 6 - check pmm-agent status 
     Displays current PMM agent state and configuration

     option 7 - pmm-admin command off container with flag: list services --service-type=mongodb 
     Lists active monitored services
 
     option 8 - start pbm-client within the different MongoDB containers 
     Starts PBM agent inside all MongoDB containers except the two routers

     option 9 - re-start pbm-client within the different MongoDB containers 
     Gracefully restarts PBM agent

     option 10 - pbm status command 
     Shows current PBM state and lock info

     option 11 - pbm list current backups 
     Shows list of available backups
     
     option 12 - pbm config current config 
     Shows backup storage path, compression, etc.
     
     option 13 - pbm logs command 
     View recent PBM operation logs
          
     option 14 - pbm create backup 
     Triggers a new backup operation using pbm backup (logical or physical)

     option 15 - start all the MongoDB containers 
     Brings up all MongoDB-related Docker containers

     option 16 - pbm restore backup 
     Manual restore initiation for a named backup, (logical or physical)
     
     option 17- restart all the MongoDB containers 
     Docker restart command issued
     
     option 18 - disable pmm-agent automatic start
     This action disable the pmm-agent to  start when restart the container
     
     option 19 - disable pbm-client automatic start
     This action disable the pbm-agent to  start when restart the container
     
     option 20 - create test data (dummydata) as MongoDB shard 
     Populates the 'dummydata' database with a collection 'users' in a shard configuration, including adding a hash index
     Main purpose is to perform some level of testing and confirm the PMM Server GUI can reflect the shard breakdown
     
     option 21 - delete test data (dummydata)
     Removes test documents from DB
     
     option 22 - read test data (dummydata)
     Queries and displays test entries
     
     option 23 - show dbs, display the number of databases
     Displays all MongoDB databases

     option 24 - check health of the MongoDB cluster
     Uses rs.status(), db.serverStatus(), etc.

     option 25 - get stats pf the MongoDB cluster 
     db.stats() per database
     
     option 26 - get mongodb version 
     Prints db.version()
     
     option 27 - get db.isMaster 
     Show primary/secondary role info
     
     option 28 - getShardDistribution for the dummydata databases 
     Useful for validating shard balance
     
     option 29 - connect to container router-02 bash 
     Enter specific MongoDB containers interactively, and enabling the env (export PBM_MONGODB_URI) to be able to perform pbm commands
     
     option 30 - connect to container config-01 bash 
     Enter specific MongoDB containers interactively, and enabling the env (export PBM_MONGODB_URI) to be able to perform pbm commands

     option 31 - connect to container shard-01-a bash 
     Enter specific MongoDB containers interactively, and enabling the env (export PBM_MONGODB_URI) to be able to perform pbm commands
     
     option 32 - connect to container shard-02-a bash 
     Enter specific MongoDB containers interactively, and enabling the env (export PBM_MONGODB_URI) to be able to perform pbm commands
     
     option 33 - connect_to_container shard-03-a bash 
     Enter specific MongoDB containers interactively, and enabling the env (export PBM_MONGODB_URI) to be able to perform pbm commands
     
     option 34 - pkill -f pbm-client within the MongoDB containers
     Terminates PBM client process inside container
     
     option 35 - tail -f ./logs/pmm*.log
     Live monitor pmm logs (tail -f)
     
     option 36 - tail -f ./logs/pbm*.log
     Live monitor pmm logs (tail -f)

     option 37 - Start the mongos (routers) docker containers only
     Required after logical restores, to avoid writes to cluster
     
     option 39 - re-configure the pbm config backup path
     Update remote storage config
     
     This option is a bit unique, pending on where you initiated the pbm backup command from
     
     If it was initiated fromm this script, the default path should be /backup/default
     If it was initiated fromm the PMM Server GUI side, the path would be /backup/<cluster name>

     So it is very important to look at the /backup folder for the specific sub-folder based on the backup file date 
EOF
    msg "${NC}"
}
#######################################
# ++ function manual_function_select_options
#######################################
function sub_menu_selection {
   #
   msg "\n${BOLD}${CYAN}Solution Version: $VERSION ${NC}"
   msg "${BOLD}${ORANGE}$WARNING_MESSAGE ${NC}"
   msg "${BOLD}$INFORMATION_MESSAGE, Running Script: $(basename "${BASH_SOURCE[0]}") (version: $SCRIPT_VERSION) ${NC}"
  
   msg "\n 1) add pmm user and roles within MongoDB  2) setup pmm-agent setup (--force) PREFERRED OPTION     3) setup pmm-agent pbm-admin config (--force)"
   msg " 4) start pmm                              5) register mongodb services                            6) check pmm-agent OS service"
   msg " 7) pmm-admin (status, inventory list...)  8) start pbm-agent within mongodb containers            9) re-start pbm-client within mongodb containers "
   msg "10) pbm status                            11) pbm list current backup list                        12) pbm config current config"     
   msg "13) pbm logs                              14) pbm create backup                                   15) start all the MongoDB containers"
   msg "16) pbm restore                           17) restart all the mongodb containers                  18) disable pmm-client automatic start "
   msg "19) disable pbm-client automatic start    20) create test data(dummydata) as MongoDB sharded      21) delete test data (dummydata) "
   msg "22) read test data (dummydata)            23) show dbs                                            24) check MongoDB cluster health"
   msg "25) get stats from the cluster            26) get mongodb version                                 27) get db.isMaster "
   msg "28) getShardDistribution                  29) connect to container router-02 bash                 30) connect to container config-01 bash "
   msg "31) connect to container shard-01-a bash  32) connect to container shard-02-a bash                33) connect to container shard-03-a bash  "
   msg "34) pkill -f pbm-client                   35) tail -f ./logs/pmm*.log                             36) tail -f ./logs/pbm*.log"
   msg "37) Start the mongos (routers) docker containers only                                             38) re-configure the pbm config backup path"
   msg "39) Get docker container information      40) unregister pmm-agent (--force) from all containers" 
   msg "41) help                                  42) exit\n"
}
#
#
#
function manual_function_select_options {
  #
  while true; do
    sub_menu_selection
    read -r -p "Please select option to execute on [1-42 ): " choice_main_menu
    case $choice_main_menu in
      1)msg "\nOption 1 - add pmm user and roles within MongoDB\n"
        #
        #function_get_mongodb_adm_info 
        check_cashed_function_get_mongodb_adm_info
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #./add-PERCONA-pmm-client-mongodb_user_roles.sh
        function_add-PERCONA-pmm-client-mongodb_user_roles
        #
			  read -r -p "[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;

      2)msg "\nOption 2 - setup pmm-agent setup (--force) PREFERRED OPTION\n"
        #
        # Need to keep track of container information 
        # is case we get our of sync with the PMM Server side 
        echo "MongoDB container information collected on this date: $(date)" > /tmp/container_information.txt
        function_setup_configure_pmm
        #
        cat /tmp/container_information.txt
        #
			  read -r -p "[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;

      3)msg "\nOption 3 -  setup pmm-agent pbm-admin config (--force)\n"
        #
        #
        # Need to keep track of container information 
        # is case we get our of sync with the PMM Server side 
        echo "MongoDB container information collected on this date: $(date)" > /tmp/container_information.txt
        #
        function_setup_configure_pmm_force
        #
        cat /tmp/container_information.txt
        #
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;

      4) msg "\nOption 4 - start pmm\n"
        #    
        function_start_pmm
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass  
        ;;
  
      5)msg "\nOption 5 - register mongodb services\n"
        #   
        function_register_mongodb_services 
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		    
        ;;

      6)msg "\nOption 6 - check pmm-agent OS service\n"
        #     
        function_check_pmm-client_status 
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	

      7)msg "\nOption 7 - pmm-admin (status , inventory list ...)\n"
        #         
        function_pmm-admin_command_which_container
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;

      8)msg "\nOption 8 - star pbm-agent within mongodb containers\n"
        #    
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_start_pbm
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	

      9)msh "\nOption 9 - re-start pbm-client within mongodb containers\n"
        #      
        function_re-start_pbm
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		       
        ;;  
     
      10)msg "\noption 10 -  pbm status\n" 
        #       
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_pbm-client_command "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "status"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	         

	    11)msg "\nOption 11 - pbm list\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        # 
        function_pbm-client_command "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "list"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # he DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	   

      12)msg "\nOption 12 - pbm config current config\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_pbm-client_command "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "config"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	   

      13)msg "\nOption 13 - pbm logs\n"
        #         
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_pbm-client_command "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin" "logs"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	         

      14)msg "\nOption 14 - pbm create backup\n"
        #          
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_pbm-execute_backup "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	

      15) msg "\nOption 15 - start all the MongoDB containers\n"
        #         
        msg  "\nStarting container :\n" 
        docker start router-01 
        docker start router-02 
        docker start mongo-config-01 
        docker start mongo-config-02 
        docker start mongo-config-03 
        docker start shard-01-node-a    
        docker start shard-01-node-b 
        docker start shard-01-node-c   
        docker start shard-02-node-a    
        docker start shard-02-node-b       
        docker start shard-02-node-c    
        docker start shard-03-node-a    
        docker start shard-03-node-b      
        docker start shard-03-node-c   
        #
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	
   
      16)msg "\nOption 16 -  pbm restore\n"
        # 
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #       
        function_pbm_restore_backup "mongo-config-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;      

      17) msg "\nOption 17 - restart all the mongodb containers\n"
        #        
    
        msg "\nRestarting all the MongoDB container :\n" 

        docker restart router-01 
        docker restart router-02 
        docker restart mongo-config-01 
        docker restart mongo-config-02 
        docker restart mongo-config-03 
        docker restart shard-01-node-a    
        docker restart shard-01-node-b 
        docker restart shard-01-node-c   
        docker restart shard-02-node-a    
        docker restart shard-02-node-b       
        docker restart shard-02-node-c    
        docker restart shard-03-node-a    
        docker restart shard-03-node-b      
        docker restart shard-03-node-c   

			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null #the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	  

      18) msg "\nOption 18 - disable pmm-client automatic start\n"
        #      
        function_disable_pmm-client_automatic_start
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		         
        ;;	 

      19)msg "\nOption 19 - disable pbm-client automatic start\n"
        #         
        function_disable_pbnm-client_automatic_start

			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 	           
        ;;	 

      20)msg "\nOption 20 - create test data(dummydata) as MongoDB sharded\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_create_test-data_shard "router-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	    

      21)msg "\nOption 21 - delete test data (dummydata)\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_delete_dummydata_DB_collection "router-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass    
        ;;	        

      22)msg "\nOption 22 - read test data (dummydata)\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_read_dummy_data "router-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass    
        ;;	  

      23)msg "\nOption 23 -  show dbs\n" 
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_show_db "router-01"
        function_show_db "mongo-config-01"
        function_show_db "shard-01-node-a"
        function_show_db "shard-02-node-a"
        function_show_db "shard-03-node-a"                      
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	 

      24)msg "\nOption 24 -  check MongoDB cluster health\n"
        #         
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_check_health_of_cluster "mongo-config-01"
        function_check_health_of_cluster "shard-01-node-a"
        function_check_health_of_cluster "shard-02-node-a"
        function_check_health_of_cluster "shard-03-node-a"                      
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 			   
        ;;	  

      25)msg "\nOption 25 - get stats from the cluster\n"
        #         
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_get_stats_cluster "mongo-config-01"
        function_get_stats_cluster "shard-01-node-a"
        function_get_stats_cluster "shard-02-node-a"
        function_get_stats_cluster "shard-03-node-a"                      
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	  

      26)msg "\nOption 26 - get mongodb version\n"
         #        
         #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_get_mongodb_version "router-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	 
 
      27)msg  "\nOption 27 - get db.isMaster\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        #
        function_get_dbisMaster  "mongo-config-01"
        function_get_dbisMaster  "shard-01-node-a"
        function_get_dbisMaster  "shard-02-node-a"
        function_get_dbisMaster  "shard-03-node-a"  
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	 
 
      28)msg "\nOption 28 - getShardDistribution\n"
        #        
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_getShardDistribution "router-01"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;	 

     29)msg "\nOption 29 - connect to container router-02 bash\n"
        #      
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_connect_to_container_bash "router-02" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 
        ;;   

     30)msg "\nOption 30 - connect to container config-01 bash\n"
        #      
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_connect_to_container_bash "mongo-config-01" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;      

     31)msg "\nOption 31 - connect to container shard-01-a bash\n"
        #       
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_connect_to_container_bash "shard-01-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass    
        ;;       

     32)msg "\nOption 32 - connect to container shard-02-a bash\n"
        #       
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_connect_to_container_bash "shard-02-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass 		   
        ;;       

     33)msg "\nOption 33 - connect to container shard-03-a bash\n"
        #       
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_connect_to_container_bash  "shard-03-node-a" "mongodb://$PERCONA_MONGODB_PMM_USERNAME:$PERCONA_MONGODB_PMM_PASSWORD@localhost:27017/?authSource=admin"
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;       

     34)msg "\nOption 34 - pkill -f pbm-client\n"
        #       
        #
        function_pkill-pbm-client_within_mongodb_containers "mongo-config-01" 
        function_pkill-pbm-client_within_mongodb_containers "mongo-config-02" 
        function_pkill-pbm-client_within_mongodb_containers "mongo-config-03" 
        function_pkill-pbm-client_within_mongodb_containers "shard-01-node-a" 
        function_pkill-pbm-client_within_mongodb_containers "shard-01-node-b" 
        function_pkill-pbm-client_within_mongodb_containers "shard-01-node-c" 
        function_pkill-pbm-client_within_mongodb_containers "shard-02-node-a"
        function_pkill-pbm-client_within_mongodb_containers "shard-02-node-b" 
        function_pkill-pbm-client_within_mongodb_containers "shard-02-node-c" 
        function_pkill-pbm-client_within_mongodb_containers "shard-03-node-a" 
        function_pkill-pbm-client_within_mongodb_containers "shard-03-node-b" 
         function_pkill-pbm-client_within_mongodb_containers "shard-03-node-c" 
        # 
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;  
    
     35)msg "\nOption 35 - tail -f ./logs/pmm*.log\n"
        #       
        #
        tail -f ./logs/pmm*.log
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;  

      36)msg "\nOption 36 - tail -f ./logs/pbm*.log\n"
        #       
        #
        tail -f ./logs/pbm*.log
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;  

      37)msg "\nOption 37 - Start the mongos (routers) docker containers only\n" 
        #       
        #
        docker start router-01
        docker start router-02
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;  

      38)msg "\nOption 38 - re-configure the pbm config backup path\n"
        #       
        #
        #function_pmm-client-agent 
        check_cashed_function_pmm-client-agent
        #
        function_recreate_pbm_config_file  "mongo-config-01" "/backup"
        #
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass   
        ;;  

      39)msg "\nOption 39 - Get MongoDB docker container information\n"
        #    
        get_container_information "router-01" 
        get_container_information "router-02"          
        get_container_information "mongo-config-01" 
        get_container_information "mongo-config-02" 
        get_container_information "mongo-config-03" 
        get_container_information "shard-01-node-a" 
        get_container_information "shard-01-node-b" 
        get_container_information "shard-01-node-c" 
        get_container_information "shard-02-node-a" 
        get_container_information "shard-02-node-b" 
        get_container_information "shard-02-node-c" 
        get_container_information "shard-03-node-a" 
        get_container_information "shard-03-node-b" 
        get_container_information "shard-03-node-c" 
        #
			  read -r -p"[Hit Return] to return to the main menu option: " DUMMY_RESP
        echo "$DUMMY_RESP" > /dev/null # the DUMMY_RESP variable is NOT used, implemented this approach to get the shellcheck pass  
        ;;

      40)msg "\nOption 40 - unregister pmm-agent (--force) from all containers\n"
        #
        function_unregister_pmm_agent
        ;;

      41)msg "\nOption 41 - help\n"
        #        
        help_menu_function
        ;;

      42) msg "\nOption 42 - exit\n"
        #        
        break
        ;;

      *)  # Handle invalid input
        msg "Invalid selection. Please choose a number between 1 and 42"
        ;;
    esac
  done
}
#
# **********************
# * main code section  *
# **********************
#
    setup_colors
    manual_function_select_options
exit