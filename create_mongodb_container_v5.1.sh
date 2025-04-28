#!/bin/bash
#
VERSION="BETA 5.1 creating a custom MongoDB 8.x version based on Percona MongoDB (Enterprise like) within docker containers with mongodb shards and replication sets"
#  WARNING There is no warranty on this script, use this script at your own risk
WARNING_MESSAGE="WARNING There is no warranty on this script, use this script at your own risk"
#  This script has not been fully optimized
INFORMATION_MESSAGE="This script has not been fully optimized"
#
SCRIPT_VERSION="5.1"
# 
# History:
#  - BETA 5.0: Original release 
#              This script is based on some of the content from - https://github.com/minhhungit/mongodb-cluster-docker-compose
#  - BETA 5.1:  
#             Modified this script to include the use of:
#                 - Percona Open Source MongoDB  https://www.percona.com/mongodb/software/mongodb-distribution instead of the default MongoDB CE
#                  - Percona Monitoring and Management
#                  - Percona Backup for MongoDB
#              Added some logic to run this script in a CI/CD pipeline 
#              Optimized a few areas of the script, and cleaned the bash syntax 
#              Added support for both logical and physical Percona (bpm) backup & restore 
#
# Disclaimer 
#  The outcome of this script is NOT supported by MongoDB Inc or by Percona under any of their commercial support
#  subscriptions or otherwise
#
# FEEL FREE to modify to your liking 
#
# Global variables
#
PERCONA_SOFTWARE="percona-release_latest.jammy_all.deb" # key software package from Percona required to build the Docker image 
SOLUTION_HOME_DIR="/mongodb" # This mount point of folder must exist before the this script can be executed 
SILENT=''
INPUT_MONGODB_ADM_USERNAME=''
INPUT_MONGODB_ADM_PASSWORD=''
CREATE_MONGODB_SUCCESS='N'
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
# -T	-o functrace	Allow tracing/debugging in functions and subshells.
# -E	-o errtrace	Ensure trap ERR applies in subshells.
# -H	-o histexpand	Enable ! history expansion.
# -m	-o monitor	Enable job control (default in interactive shells).
# 
# 
# set +e  # Disable "exit on error"
# set +x  # Disable debugging (tracing)
#
set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT
#
#######################################
# Clean up setup if interrupt.
#######################################
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
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
    NC='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' CYAN='\033[0;36m'
    CYAN='\033[0;36m' BOLD='\033[1m'
  else
    NC='' RED='' GREEN='' ORANGE='' CYAN='' CYAN='' BOLD=''
  fi
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
# Prints message to stderr with new line at the end.
#######################################
msg() {
  echo >&2 -e "${1-}"
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
# ++ function get_mongodb_adm_user_password
#######################################
function get_mongodb_adm_user_password {
     #
     msg "\n${CYAN} We need to collect the ${BOLD}${ORANGE} main MongoDB ADMIN (root role) username & password ${NC}"
     msg "${CYAN} that will be required later in this script ${NC}"
     #
    if [[ "$SILENT" = "Y" ]] ; then 
       RESP="Y"
       MONGODB_ADM_USER="$INPUT_MONGODB_ADM_USERNAME"
    else    
       msg "\nMain MongoDB ADMIN (root) username ?" 
       read -r -p "Please enter your response " RESP_MONGODB_ADM_USER
       MONGODB_ADM_USER="$RESP_MONGODB_ADM_USER"
    fi
    # 
    if [[ "$SILENT" = "Y" ]] ; then 
      RESP="Y"
      MONGODB_ADM_PASSWORD="$INPUT_MONGODB_ADM_PASSWORD"
    else
       msg "\nMain MongoDB ADMIN (root) password ?"
       read -r -p "Please enter your response  " RESP_MONGODB_ADM_PASSW
       MONGODB_ADM_PASSWORD="$RESP_MONGODB_ADM_PASSW"
    fi   
    #
    #
    msg "${CYAN} \n main mongodb administrator username:${NC} ${BOLD} $MONGODB_ADM_USER ${NC}"
    msg "${CYAN} main mongodb administrator password:${NC} ${BOLD} $MONGODB_ADM_PASSWORD ${NC}"
    #
    if [[ "$SILENT" = "Y" ]] ; then 
       RESP="Y"
    else
       msg "\nIs the above information correct  ?"
       read -r -p "Please enter your response (Y/N) [[ default: Y ]]  " RESP
    fi
    #
    RESP=${RESP^^} # convert to upper case 
    if [[ "$RESP" = "N" ]]  ; then
     die "${CYAN} Answer was to stop  ${NC}"
    else
      msg "\n${CYAN} Continuing ...  $0 ${NC}"
    fi                
}
#######################################
# ++ function clean_folder
#######################################
function clean_folder {
     #
     #
     #
    cd "$SOLUTION_HOME_DIR"
    pwd
     #
    if [[ "$SILENT" = "Y" ]] ; then 
        RESP="Y"
    else
       msg "\nAre you sure you want to trigger this next action as this will destroy everything in the $SOLUTION_HOME_DIR sub-folders"
       read -r -p "Please enter your response (Y/N) [[ default: Y ]]  " RESP
    fi  

   RESP=${RESP^^} # convert to upper case 
   if [[ "$RESP" = "N" ]] ; then
      msg "${ORANGE}Skipping re-creating $SOLUTION_HOME_DIR and sub-folder${NC}"
   else 
       msg "\nContinuing ...  the clean_folder function " 
       msg " Performing rm -Rf $SOLUTION_HOME_DIR/mongodb_cluster_* action" 

      if [[ -d "$SOLUTION_HOME_DIR/data" ]] ; then
         msg "Deleting  $SOLUTION_HOME_DIR/data/*"
         rm -Rf $SOLUTION_HOME_DIR/data
      fi

      if [[ -d "$SOLUTION_HOME_DIR/scripts" ]] ; then
         msg "Deleting  $SOLUTION_HOME_DIR/scripts/*"
         rm -Rf $SOLUTION_HOME_DIR/scripts
      fi
  
      if [[ -d "$SOLUTION_HOME_DIR/mongodb-build/" ]] ; then
         msg "Deleting  $SOLUTION_HOME_DIR/mongodb-build/"
         rm -Rf $SOLUTION_HOME_DIR/mongodb-build/
      fi

      if [[ -d "$SOLUTION_HOME_DIR/backup-percona-mongodb" ]] ; then
         msg "Deleting $SOLUTION_HOME_DIR/backup-percona-mongodb" 
         rm -Rf $SOLUTION_HOME_DIR/backup-percona-mongodb    
      fi    

      if [[ -d "$SOLUTION_HOME_DIR/logs" ]] ; then
         msg "Deleting $SOLUTION_HOME_DIR/logs" 
         rm -Rf $SOLUTION_HOME_DIR/logs   
      fi   

      if [[ -d "$SOLUTION_HOME_DIR/mongologs" ]] ; then
         msg "Deleting $SOLUTION_HOME_DIR/mongologs" 
         rm -Rf $SOLUTION_HOME_DIR/mongologs  
      fi 
      #
      ls -lht 
      #
      #
      msg " Performing mkdir -p $SOLUTION_HOME_DIR/data"
      mkdir  $SOLUTION_HOME_DIR/data
      msg " Performing mkdir -p $SOLUTION_HOME_DIR/mongologs"
      mkdir  $SOLUTION_HOME_DIR/mongologs
      #
      #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_router01_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_router01_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_router01_db
     #mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_router01_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_router01_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_router02_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_router02_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_router02_db
     #mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_router02_config
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_router02_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/ongodb_cluster_configsvr01_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr01_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr01_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr01_config
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr01_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr02_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr02_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr02_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr02_config
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr02_log 
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr03_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr03_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr03_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_configsvr03_config 
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_configsvr03_log 
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_a_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_a_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_a_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_a_config
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_a_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_b_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_b_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_b_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_b_config  
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_b_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_c_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_c_log"
     mkdir  $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_c_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard01_c_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard01_c_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_a_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_a_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_a_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_a_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_a_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_b_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_b_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_b_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_b_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_b_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_c_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_c_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_c_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard02_c_config
     mkdir  $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard02_c_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_a_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_a_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_a_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_a_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_a_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_b_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_b_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_b_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_b_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_b_log
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_c_db and $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_c_log"
     mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_c_db
     #mkdir $SOLUTION_HOME_DIR/data/mongodb_cluster_shard03_c_config
     mkdir $SOLUTION_HOME_DIR/mongologs/mongodb_cluster_shard03_c_log
     # 
     msg " Performing chown -R mongodb:mongodb ./data and  chmod -R 755 ./data"  
     chown -R mongodb:mongodb ./data
     chmod -R 755 ./data
     msg " Performing chown -R mongodb:mongodb ./mongologs and  chmod -R 755 ./mongologs"  
     chown -R mongodb:mongodb ./mongologs
     chmod -R 755 ./mongologs
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/backup-percona-mongodb"
     #
     mkdir -p $SOLUTION_HOME_DIR/backup-percona-mongodb
     chown -R mongodb:mongodb $SOLUTION_HOME_DIR/backup-percona-mongodb 
     chmod 777 $SOLUTION_HOME_DIR/backup-percona-mongodb
     #
     msg " Performing mkdir -p $SOLUTION_HOME_DIR/logs"
     #
     mkdir -p $SOLUTION_HOME_DIR/logs
     chown -R mongodb:mongodb $SOLUTION_HOME_DIR/logs
     chmod 777 $SOLUTION_HOME_DIR/logs
   fi
}
#######################################
# ++ function create_docker-compose_file
#######################################
function create_docker-compose_file {
    #
    msg "========================"
    msg "Current folder: $(pwd)"
    msg "========================"
    
    #
    if [[ "$SILENT" = "Y" ]]  ; then 
        RESP="Y"
    else
       msg "\nAre you sure you want to trigger this action as this will re-create all required files including the docker-compose.yml file ?"
       read -r -p "Please enter your response (Y/N) [[ default: Y ]] " RESP
    fi
    # 
    RESP=${RESP^^} # convert to upper case 
    if [[ "$RESP" = "N" ]] ; then
      msg "${ORANGE}Skipping re-creating the docker-compose.yml file ... ${NC}"
    else
      msg "${CYAN}Continuing ...  the create_docker-compose_file function ${NC}" 
      msg "${CYAN}Creating the Dockerfile and required folders ... ${NC}" 
      mkdir -p $SOLUTION_HOME_DIR/mongodb-build/
      mkdir -p $SOLUTION_HOME_DIR/mongodb-build/auth
      mkdir -p $SOLUTION_HOME_DIR/scripts/
      #
      msg  -e "${CYAN}Performing chown -R mongodb:mongodb $SOLUTION_HOME_DIR/mongodb-build/ and  chmod -R 755 $SOLUTION_HOME_DIR/mongodb-build/${NC}" 
      chown -R mongodb:mongodb $SOLUTION_HOME_DIR/mongodb-build/
      chmod -R 755 $SOLUTION_HOME_DIR/mongodb-build/
      #
      msg "${CYAN}Performing chown -R mongodb:mongodb $SOLUTION_HOME_DIR/scripts/ and  chmod -R 755 $SOLUTION_HOME_DIR/scripts/${NC}"
      chown -R mongodb:mongodb $SOLUTION_HOME_DIR/scripts/
      chmod -R 755 $SOLUTION_HOME_DIR/scripts/
      #
      # Let's go create the key file 
      #
      create_mongodb_keyfile
      #		
      msg "${CYAN}Creating $SOLUTION_HOME_DIR/mongodb-build/Dockerfile file... ${NC}" 
      #
      echo "# Percona PMM is empty for now" > $SOLUTION_HOME_DIR/mongodb-build/start_pmm_file.sh
      echo "echo file is empty> start_pmm_file.txt" >> $SOLUTION_HOME_DIR/mongodb-build/start_pmm_file.sh
      # 
      echo "# Percona PBM is empty for now" > $SOLUTION_HOME_DIR/mongodb-build/start_pbm_file.sh
      echo "echo file is empty > start_pbm_file.txt" >> $SOLUTION_HOME_DIR/mongodb-build/start_pbm_file.sh
      #
      #
      #
      if [[ -f "$SOLUTION_HOME_DIR/mongodb-build/router_entrypoint.sh" ]] ; then 
          msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/scripts/router_entrypoint.sh, as a new one will be created ... ${NC}"
          rm -f $SOLUTION_HOME_DIR/mongodb-build/router_entrypoint.sh
      fi
      #
      if [[ -f "$SOLUTION_HOME_DIR/mongodb-build/config_entrypoint.sh" ]] ; then 
          msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/scripts/config_entrypoint.sh, as a new one will be created ... ${NC}"
          rm -f $SOLUTION_HOME_DIR/mongodb-build/config_entrypoint.sh
      fi
      #
      if [[ -f "$SOLUTION_HOME_DIR/mongodb-build/shard01_entrypoint.sh" ]] ; then 
          msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/mongodb-build/shard01_entrypoint.sh, as a new one will be created ... ${NC}"
            rm -f $SOLUTION_HOME_DIR/mongodb-build/shard01_entrypoint.sh
      fi
      #
      if [[ -f "$SOLUTION_HOME_DIR/mongodb-build/shard02_entrypoint.sh" ]] ; then 
           msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/mongodb-build/shard02_entrypoint.sh, as a new one will be created ... ${NC}"
           rm -f $SOLUTION_HOME_DIR/mongodb-build/shard02_entrypoint.sh
      fi
      #
      if [[ -f "$SOLUTION_HOME_DIR/mongodb-build/shard03_entrypoint.sh" ]] ; then 
          msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/mongodb-build/shard03_entrypoint.sh file, as a new one will be created ... ${NC}"
          rm -f $SOLUTION_HOME_DIR/mongodb-build/shard03_entrypoint.sh
      fi
      #
      msg "====================="
      msg "Current Folder : $(pwd) STEP 1 "
      msg " ======================"
      #
      # ++ router_entrypoint.sh 
      # 
      msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/router_entrypoint.sh ... ${NC}"
      #
      tee $SOLUTION_HOME_DIR/mongodb-build/router_entrypoint.sh 1> /dev/null <<EOF
#!/bin/bash
set -e
#
echo "Starting MongoDB..."
mongos --port 27017 --configdb rs-config-server/configsvr01:27017,configsvr02:27017,configsvr03:27017 --bind_ip_all --keyFile /tmp/mongodb-keyfile  &
#
# Start Percona PMM Client only if the script exists and is non-empty
if [[ -s ./start_pmm_file.sh ]]; then
    echo "Starting Percona PMM Client..."
    chmod +x ./start_pmm_file.sh
    ./start_pmm_file.sh || msg "Warning: Failed to start PMM Client"
else
    echo "Skipping PMM Client startup: File is missing or empty."
fi
#
sleep 5
#
# Start Percona PBM Client only if the script exists and is non-empty
if [[ -s ./start_pbm_file.sh ]]; then
    echo "Starting Percona PBM Client..."
    chmod +x ./start_pbm_file.sh
    ./start_pbm_file.sh || msg "Warning: Failed to start PBM Client"
else
    echo "Skipping PBM Client startup: File is missing or empty."
fi
#
# Keep the container running in the foreground
wait
EOF
        #
        # 
        #
        msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/config_entrypoint.sh ... ${NC}"
        #
        tee $SOLUTION_HOME_DIR/mongodb-build/config_entrypoint.sh 1> /dev/null<<EOF
#!/bin/bash
set -e
#
echo "Starting MongoDB..."
mongod --port 27017 --configsvr --replSet rs-config-server --keyFile /tmp/mongodb-keyfile --bind_ip_all --wiredTigerCacheSizeGB 1 --config /etc/mongod.conf &
#
sleep 5
#
# Start Percona PMM Client only if the script exists and is non-empty
if [[ -s ./start_pmm_file.sh ]]; then
    echo "Starting Percona PMM Client..."
    chmod +x ./start_pmm_file.sh
    ./start_pmm_file.sh || msg "Warning: Failed to start PMM Client"
else
    echo "Skipping PMM Client startup: File is missing or empty."
fi
#
sleep 5
#
# Start Percona PBM Client only if the script exists and is non-empty
if [[ -s ./start_pbm_file.sh ]]; then
    echo "Starting Percona PBM Client..."
    chmod +x ./start_pbm_file.sh
    ./start_pbm_file.sh || msg "Warning: Failed to start PBM Client"
else
    echo "Skipping PBM Client startup: File is missing or empty."
fi
#
# Keep the container running in the foreground
wait
EOF
        #
        #
        #
        msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/shard01_entrypoint.sh ... ${NC}"
        #
        tee $SOLUTION_HOME_DIR/mongodb-build/shard01_entrypoint.sh 1> /dev/null <<EOF
#!/bin/bash
set -e

echo "Starting MongoDB..."

mongod --port 27017 --shardsvr --replSet rs-shard-01 --keyFile /tmp/mongodb-keyfile --bind_ip_all --wiredTigerCacheSizeGB 1 --config /etc/mongod.conf &

#
sleep 5
#
# Start Percona PMM Client only if the script exists and is non-empty
if [[ -s ./start_pmm_file.sh ]]; then
    echo "Starting Percona PMM Client..."
    chmod +x ./start_pmm_file.sh
    ./start_pmm_file.sh || msg "Warning: Failed to start PMM Client"
else
    echo "Skipping PMM Client startup: File is missing or empty."
fi

sleep 5

# Start Percona PBM Client only if the script exists and is non-empty
if [[ -s ./start_pbm_file.sh ]]; then
    echo "Starting Percona PBM Client..."
    chmod +x ./start_pbm_file.sh
    ./start_pbm_file.sh || msg "Warning: Failed to start PBM Client"
else
    echo "Skipping PBM Client startup: File is missing or empty."
fi

# Keep the container running in the foreground
wait
EOF
        #
        #
        #
        msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/shard02_entrypoint.sh ... ${NC}"
        #
        tee $SOLUTION_HOME_DIR/mongodb-build/shard02_entrypoint.sh 1> /dev/null <<EOF
#!/bin/bash
set -e

echo "Starting MongoDB..."

mongod --port 27017 --shardsvr --replSet rs-shard-02 --keyFile /tmp/mongodb-keyfile --bind_ip_all --wiredTigerCacheSizeGB 1 --config /etc/mongod.conf &
#
sleep 5
#
# Start Percona PMM Client only if the script exists and is non-empty
if [[ -s ./start_pmm_file.sh ]]; then
    echo "Starting Percona PMM Client..."
    chmod +x ./start_pmm_file.sh
    ./start_pmm_file.sh || msg "Warning: Failed to start PMM Client"
else
    echo  "Skipping PMM Client startup: File is missing or empty."
fi

sleep 5

# Start Percona PBM Client only if the script exists and is non-empty
if [[ -s ./start_pbm_file.sh ]]; then
    echo "Starting Percona PBM Client..."
    chmod +x ./start_pbm_file.sh
    ./start_pbm_file.sh || msg "Warning: Failed to start PBM Client"
else
    echo "Skipping PBM Client startup: File is missing or empty."
fi

# Keep the container running in the foreground
wait
EOF
         #
         #
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/shard03_entrypoint.sh ... ${NC}"
         #
        tee $SOLUTION_HOME_DIR/mongodb-build/shard03_entrypoint.sh 1> /dev/null <<EOF
#!/bin/bash
set -e

echo "Starting MongoDB..."

mongod --port 27017 --shardsvr --replSet rs-shard-03 --keyFile /tmp/mongodb-keyfile --bind_ip_all --wiredTigerCacheSizeGB 1 --config /etc/mongod.conf &

#
sleep 5
#
# Start Percona PMM Client only if the script exists and is non-empty
if [[ -s ./start_pmm_file.sh ]]; then
    echo "Starting Percona PMM Client..."
    chmod +x ./start_pmm_file.sh
    ./start_pmm_file.sh || msg "Warning: Failed to start PMM Client"
else
    echo "Skipping PMM Client startup: File is missing or empty."
fi

sleep 5

# Start Percona PBM Client only if the script exists and is non-empty
if [[ -s ./start_pbm_file.sh ]]; then
    echo "Starting Percona PBM Client..."
    chmod +x ./start_pbm_file.sh
    ./start_pbm_file.sh || msg "Warning: Failed to start PBM Client"
else
    echo "Skipping PBM Client startup: File is missing or empty."
fi

# Keep the container running in the foreground
wait
EOF
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-01.conf  ... ${NC}"
         # 
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-01.conf  1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-router-01.log

[program:mongod]
command=/router_entrypoint.sh
autostart=true
autorestart=true
stdout_logfile=/log/mongos-router-01.log
stderr_logfile=/log/mongos-router-01.err         
EOF
         #
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-01.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-02.conf  ... ${NC}"
         # 
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-02.conf  1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-router-02.log

[program:mongod]
command=/router_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongos-router-02.log
stderr_logfile=/log/mongos-router-02.err         
EOF
         # 
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-router-02.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-01.conf  ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-01.conf  1> /dev/null<<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-config-01.log

[program:mongod]
command=/config_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-config-01.log
stderr_logfile=/log/mongod-config-01.err         
EOF
         #          
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-01.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-02.conf  ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-02.conf  1> /dev/null<<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-config-02.log

[program:mongod]
command=/config_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-config-02.log
stderr_logfile=/log/mongod-config-02.err         
EOF
         #   
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-02.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-03.conf  ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-03.conf  1> /dev/null<<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-config-03.log

[program:mongod]
command=/config_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-config-03.log
stderr_logfile=/log/mongod-config-03.err         
EOF
         #          
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-config-03.conf
         #         
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-a.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-a.conf  1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard01-node-a.log

[program:mongod]
command=/shard01_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard01-node-a.log
stderr_logfile=/log/mongod-shard01-node-a.err
EOF
         # 
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-a.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-b.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-b.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard01-node-b.log

[program:mongod]
command=/shard01_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard01-node-b.log
stderr_logfile=/log/mongod-shard01-node-b.err         
EOF
         # 
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-b.conf
         # 
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-c.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-c.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard01-node-c.log

[program:mongod]
command=/shard01_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard01-node-c.log
stderr_logfile=/log/mongod-shard01-node-c.err         
EOF
         # 
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard01-node-c.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-a.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-a.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard02-node-a.log

[program:mongod]
command=/shard02_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard02-node-a.log
stderr_logfile=/log/mongod-shard02-node-a.err         
EOF
         #
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-a.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-b.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-b.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard02-node-b.log

[program:mongod]
command=/shard02_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard02-node-b.log
stderr_logfile=/log/mongod-shard02-node-b.err         
EOF
         #
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-b.conf
         #
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-c.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-c.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard02-node-c.log

[program:mongod]
command=/shard02_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard02-node-c.log
stderr_logfile=/log/mongod-shard02-node-c.err         
EOF
         #
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard02-node-c.conf
         #   
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-a.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-a.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard03-node-a.log

[program:mongod]
command=/shard03_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard03-node-a.log
stderr_logfile=/log/mongod-shard03-node-a.err         
EOF
        #  
        # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-a.conf
         #   
         msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-b.conf ... ${NC}"
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-b.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard03-node-b.log

[program:mongod]
command=/shard03_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard03-node-b.log
stderr_logfile=/log/mongod-shard03-node-b.err         
EOF
        #  
        # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-b.conf
        # 
        msg "${ORANGE}Creating $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-c.conf ... ${NC}"
        #
         tee $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-c.conf 1> /dev/null <<EOF
[supervisord]
nodaemon=true
logfile=/log/supervisord-shard03-node-c.log

[program:mongod]
command=/shard03_entrypoint.sh
autostart=true
autorestart=false
stdout_logfile=/log/mongod-shard03-node-c.log
stderr_logfile=/log/mongod-shard03-node-c.err         
EOF
        #  
         # cat $SOLUTION_HOME_DIR/mongodb-build/supervisord-shard03-node-c.conf
         #
         msg "====================="
         msg "Current Folder : $(pwd), STEP 2 "
         msg "======================"
         msg "${CYAN}Creating $SOLUTION_HOME_DIR/mongodb-build/Dockerfile file... ${NC}" 
         #
         tee $SOLUTION_HOME_DIR/mongodb-build/Dockerfile <<EOF
FROM mongo:8.0.4
# Set GLIBC_TUNABLES to disable rseq support
ENV GLIBC_TUNABLES=glibc.pthread.rseq=0
#
COPY $PERCONA_SOFTWARE /$PERCONA_SOFTWARE
#
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    telnet \
    iputils-ping \
    nano \
    supervisor \
    software-properties-common
#
# Removing the original mongo ce 
#
RUN apt-get remove -y \
     mongodb-org \ 
     mongodb-org-mongos \ 
     mongodb-org-server \ 
     mongodb-org-shell \
     mongodb-org-tools
#
# RUN apt-get purge -y mongodb-org*
#
RUN apt-get remove -y mongodb-mongosh
#
# Install percona-release; if dependencies are missing, fix them and reinstall
#
RUN dpkg -i /$PERCONA_SOFTWARE || (apt-get update && apt-get install -y -f && dpkg -i /$PERCONA_SOFTWARE)
#
# Enable the required repositories:
# - psmongodb80 (Percona Server for MongoDB 8.0)
# - pmm3-client (PMM Client)
# - pbm (Percona Backup for MongoDB) [channel name may vary; adjust if needed]
#
RUN percona-release enable psmdb-80 release
RUN percona-release enable pmm3-client release
RUN percona-release enable pbm release
#
# Update package lists and install PSMDB (Percona MongoDB Ent. version), PMM Client, and PBM.
RUN apt-get update && \
    bash -c '[[ -f /etc/mongod.conf ]] && mv /etc/mongod.conf /etc/mongod.conf.bak || true' && \
    apt-get install -y -o Dpkg::Options::="--force-confnew" \
        percona-server-mongodb \
        pmm-client \
        percona-backup-mongodb || \
    (apt-get update && apt-get install -y -f && \
     apt-get install -y -o Dpkg::Options::="--force-confnew" \
        percona-server-mongodb \
        pmm-client \
        percona-backup-mongodb)
#
#
#
COPY supervisord-router-01.conf /etc/supervisor/conf.d/supervisord-router-01.conf
COPY supervisord-router-02.conf /etc/supervisor/conf.d/supervisord-router-02.conf
#
COPY supervisord-config-01.conf /etc/supervisor/conf.d/supervisord-config-01.conf
COPY supervisord-config-02.conf /etc/supervisor/conf.d/supervisord-config-02.conf
COPY supervisord-config-03.conf /etc/supervisor/conf.d/supervisord-config-03.conf
#
COPY supervisord-shard01-node-a.conf /etc/supervisor/conf.d/supervisord-shard01-node-a.conf
COPY supervisord-shard01-node-b.conf /etc/supervisor/conf.d/supervisord-shard01-node-b.conf
COPY supervisord-shard01-node-c.conf /etc/supervisor/conf.d/supervisord-shard01-node-c.conf
#
COPY supervisord-shard02-node-a.conf /etc/supervisor/conf.d/supervisord-shard02-node-a.conf
COPY supervisord-shard02-node-b.conf /etc/supervisor/conf.d/supervisord-shard02-node-b.conf
COPY supervisord-shard02-node-c.conf /etc/supervisor/conf.d/supervisord-shard02-node-c.conf
#
COPY supervisord-shard03-node-a.conf /etc/supervisor/conf.d/supervisord-shard03-node-a.conf
COPY supervisord-shard03-node-b.conf /etc/supervisor/conf.d/supervisord-shard03-node-b.conf
COPY supervisord-shard03-node-c.conf /etc/supervisor/conf.d/supervisord-shard03-node-c.conf
#
COPY router_entrypoint.sh / 
COPY config_entrypoint.sh / 
COPY shard01_entrypoint.sh /
COPY shard02_entrypoint.sh /
COPY shard03_entrypoint.sh /
#
COPY start_pmm_file.sh /
COPY start_pbm_file.sh /
#
RUN chmod +x /*.sh
#
COPY /auth/mongodb-keyfile /tmp
#
RUN chmod 400 /tmp/mongodb-keyfile
RUN chown 999:999 /tmp/mongodb-keyfile   
EOF
         #
         # cat $SOLUTION_HOME_DIR/mongodb-build/Dockerfile
         #
         msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-init-configserver.js file... ${NC}" 
         #
         tee $SOLUTION_HOME_DIR/scripts/dev-init-configserver.js /dev/null <<EOF
use admin
var config = {
        "_id": "rs-config-server",
        "configsvr": true,
        "version": 1,
        "members": [
                {
                        "_id": 0,
                        "host": "configsvr01:27017",
                        "priority": 1
                },
                {
                        "_id": 1,
                        "host": "configsvr02:27017",
                        "priority": 0.5
                },
                {
                        "_id": 2,
                        "host": "configsvr03:27017",
                        "priority": 0.5
                }
        ]
};
rs.initiate(config, { force: true });
exit;
EOF
          #
          msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-init-shard01.js file... ${NC}" 
          #
          tee $SOLUTION_HOME_DIR/scripts/dev-init-shard01.js /dev/null <<EOF
use admin
var config = {
    "_id": "rs-shard-01",
    "version": 1,
    "members": [
        {
            "_id": 0,
            "host": "shard01-a:27017",
                        "priority": 1
        },
        {
            "_id": 1,
            "host": "shard01-b:27017",
                        "priority": 0.5
        },
        {
            "_id": 2,
            "host": "shard01-c:27017",
                        "priority": 0.5
        }
    ]
};
rs.initiate(config, { force: true });
exit;
EOF
         #
        msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-init-shard02.js file... ${NC}" 
        #
        tee $SOLUTION_HOME_DIR/scripts/dev-init-shard02.js 1> /dev/null <<EOF
use admin
var config = {
    "_id": "rs-shard-02",
    "version": 1,
    "members": [
        {
            "_id": 0,
            "host": "shard02-a:27017",
                        "priority": 1
        },
        {
            "_id": 1,
            "host": "shard02-b:27017",
                        "priority": 0.5
        },
        {
            "_id": 2,
            "host": "shard02-c:27017",
                        "priority": 0.5
        }
    ]
};
rs.initiate(config, { force: true });
exit;
EOF
          #
          msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-init-shard03.js file... ${NC}" 
          #
          tee $SOLUTION_HOME_DIR/scripts/dev-init-shard03.js 1> /dev/null <<EOF
use admin
var config = {
    "_id": "rs-shard-03",
    "version": 1,
    "members": [
        {
            "_id": 0,
            "host": "shard03-a:27017",
                        "priority": 1
        },
        {
            "_id": 1,
            "host": "shard03-b:27017",
                        "priority": 0.5
        },
        {
            "_id": 2,
            "host": "shard03-c:27017",
                        "priority": 0.5
        }
    ]
};
rs.initiate(config, { force: true });
exit;
EOF
          #
          msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-init-router.js file... ${NC}"  
          #
          tee $SOLUTION_HOME_DIR/scripts/dev-init-router.js 1> /dev/null <<EOF
use admin;
sh.addShard("rs-shard-01/shard01-a:27017");
sh.addShard("rs-shard-01/shard01-b:27017");
sh.addShard("rs-shard-01/shard01-c:27017");
sh.addShard("rs-shard-02/shard02-a:27017");
sh.addShard("rs-shard-02/shard02-b:27017");
sh.addShard("rs-shard-02/shard02-c:27017");
sh.addShard("rs-shard-03/shard03-a:27017");
sh.addShard("rs-shard-03/shard03-b:27017");
sh.addShard("rs-shard-03/shard03-c:27017");
exit;
EOF
         #
         msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/dev-auth.js file... ${NC}" 
         #
         tee $SOLUTION_HOME_DIR/scripts/dev-auth.js 1> /dev/null <<EOF
use admin
db.createUser({user: "$MONGODB_ADM_USER", pwd: "$MONGODB_ADM_PASSWORD", roles: [{role: "root", db: "admin"}]})
exit;
EOF
        #
        msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/disableTelemetry.js file... ${NC}"
        #
        tee $SOLUTION_HOME_DIR/scripts/disableTelemetry.js 1> /dev/null <<EOF
use admin
config.get('enableTelemetry');
disableTelemetry();
config.get('enableTelemetry');
exit;
EOF
        #
        msg "${CYAN}Creating $SOLUTION_HOME_DIR/scripts/disableTelemetry_check.js file... ${NC}"
        # 
        tee $SOLUTION_HOME_DIR/scripts/disableTelemetry_check.js 1> /dev/null <<EOF
use admin;
config.get('enableTelemetry');
exit;
EOF
         #
         # looking for the PERCONA_SOFTWARE  
         #
         if [[ -f "$PERCONA_SOFTWARE" ]] ; then
            msg "${ORANGE} found the file $PERCONA_SOFTWARE and copying it to $SOLUTION_HOME_DIR/mongodb-build.${NC}"
            cp "$PERCONA_SOFTWARE" "$SOLUTION_HOME_DIR"/mongodb-build/percona-release_latest.jammy_all.deb
         else
            msg "${BOLD} ================ ERROR ========================${NC}"
            msg "${RED} This file $PERCONA_SOFTWARE is missing in this local folder"
            msg "${ORANGE} This solution was based on this Percona software package: $PERCONA_SOFTWARE${NC}"
            msg "${ORANGE} Please go and get it from the proper website, or modify this scrip to use the version you desire${NC}"
            msg "${BOLD} ================ ERROR ========================${NC}"
            die "${ORANGE} We now need to stop this script ${NC}"
         fi
         #
         create_docker-compose.yml
         # 
         msg "Build the image first and push it to the docker register ..."
         #
         cd "$SOLUTION_HOME_DIR"/mongodb-build/
        #
        msg "${ORANGE}performing this task ==> docker build -t dev-percona-mongo:8.0.4 .${NC}"
        # 
        docker build -t dev-percona-mongo:8.0.4-2 .
        #
        docker images
        #
        cd "$SOLUTION_HOME_DIR"
    fi
}
#######################################
# ++ function create_docker-compose.yml
#######################################
function create_docker-compose.yml {
   #
   if [[ -f "$SOLUTION_HOME_DIR/docker-compose.yml" ]] ; then 
      msg "${ORANGE}Deleting the existing file $SOLUTION_HOME_DIR/docker-compose.yml, as a new one will be created ... ${NC}"
      rm $SOLUTION_HOME_DIR/docker-compose.yml
   fi
   #
   msg "${CYAN}Creating $SOLUTION_HOME_DIR/docker-compose.yml file... ${NC}" 
   #
   tee $SOLUTION_HOME_DIR/docker-compose.yml 1> /dev/null <<EOF
#version: '3.8'
services:

## Routers
  router01:
    image: dev-percona-mongo:8.0.4-2
    container_name: router-01
    privileged: true
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-router-01.conf"]
    ports:
      - 27117:27017
    restart: always
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_router01_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_router01_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup

  router02:
    image: dev-percona-mongo:8.0.4-2
    container_name: router-02
    privileged: true
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-router-02.conf"]
    ports:
      - 27118:27017
    restart: always
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_router02_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_router02_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    links:
      - router01

## Config Servers
  configsvr01:
    image: dev-percona-mongo:8.0.4-2
    container_name: mongo-config-01
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-config-01.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_configsvr01_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_configsvr01_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27119:27017
    restart: always
    links:
      - shard01-a
      - shard02-a
      - shard03-a
      - configsvr02
      - configsvr03

  configsvr02:
    image: dev-percona-mongo:8.0.4-2
    container_name: mongo-config-02
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-config-02.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_configsvr02_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_configsvr02_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27120:27017
    restart: always

  configsvr03:
    image: dev-percona-mongo:8.0.4-2
    container_name: mongo-config-03
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-config-03.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_configsvr03_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_configsvr03_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27121:27017
    restart: always

## Shards
  ## Shards 01
  shard01-a:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-01-node-a
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard01-node-a.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard01_a_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard01_a_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27122:27017
    restart: always
    links:
      - shard01-b
      - shard01-c

  shard01-b:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-01-node-b
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard01-node-b.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard01_b_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard01_b_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27123:27017
    restart: always

  shard01-c:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-01-node-c
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard01-node-c.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard01_c_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard01_c_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27124:27017
    restart: always

  ## Shards 02
  shard02-a:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-02-node-a
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard02-node-a.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard02_a_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard02_a_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27125:27017
    restart: always
    links:
      - shard02-b
      - shard02-c

  shard02-b:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-02-node-b
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard02-node-b.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard02_b_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard02_b_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27126:27017
    restart: always

  shard02-c:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-02-node-c
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard02-node-c.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard02_c_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard02_c_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27127:27017
    restart: always

  ## Shards 03
  shard03-a:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-03-node-a
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard03-node-a.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard03_a_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard03_a_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27128:27017
    restart: always
    links:
      - shard03-b
      - shard03-c

  shard03-b:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-03-node-b
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard03-node-b.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard03_b_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard03_b_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27129:27017
    restart: always

  shard03-c:
    image: dev-percona-mongo:8.0.4-2
    container_name: shard-03-node-c
    privileged: true  # Add this line
    command: ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord-shard03-node-c.conf"]
    volumes:
      - ./scripts:/scripts
      - ./data/mongodb_cluster_shard03_c_db:/var/lib/mongodb
      - ./mongologs/mongodb_cluster_shard03_c_log:/var/log/mongodb 
      - ./logs:/log
      - ./backup-percona-mongodb:/backup
    ports:
      - 27130:27017
    restart: always
EOF
}
#######################################
# ++ function create_mongodb_keyfile
#######################################
function create_mongodb_keyfile {
   #
   if [[ "$SILENT" = "Y" ]] ; then 
      RESP="Y"
   else
      msg "\nAre you sure you want to trigger this action as this will re-create the keyfile  ?"
      read -r -p "Please enter your response (Y/N) [[ default: Y ]] " RESP
   fi

  RESP=${RESP^^} # convert to upper case 
  if [[ "$RESP" = "N" ]]  ; then
   msg "${ORANGE}Skipping recreating the create_mongodb_keyfile function${NC}" 
  else  
     msg "Continuing ...  the create_mongodb_keyfile function "    
     openssl rand -base64 756 > mongodb-keyfile
     pwd
     chown mongodb:mongodb mongodb-keyfile
     ls -l mongodb-keyfile
     cp mongodb-keyfile /mongodb/mongodb-build/auth/mongodb-keyfile
     chmod 400 /mongodb/mongodb-build/auth/mongodb-keyfile
     ls -l /mongodb/mongodb-build/auth/mongodb-keyfile
  fi    
  # 
}
#######################################
# ++ function create_docker_compose 
#######################################
function create_docker_compose  {
    #
    if [[ "$SILENT" = "Y" ]]  ; then 
       RESP="Y"
    else
       msg "\nAre you sure you want to trigger this action as this will re-execute the docker compose command  ?"
       read -r -p "Please enter your response (Y/N) [[ default: Y ]] " RESP
    fi

   RESP=${RESP^^} # convert to upper case 
   if [[ "$RESP" = "N" ]] ; then
       msg "${ORANGE}Skipping action from the create_docker_compose function${NC}"
    else    
       msg "${CYAN}Continuing ...  the setting_mongodb function${NC} " 
			 cd $SOLUTION_HOME_DIR
			 docker compose up -d
    fi
    #
    if [[ "$SILENT" = "Y" ]] ;  then 
       # 30 second wait and no messages 
       wait_with_message 30 "Need to wait a bit for all the containers to start"
    fi
}
#######################################
# ++ function create_setting_mongodb
#######################################
function create_setting_mongodb  {
  #
  if [[ "$SILENT" = "Y" ]] ; then 
      RESP="Y"
  else   
     msg "\nAre you sure you want to trigger this action as this will destroy and reset all the current settings  ?"
     read -r -p "Please enter your response (Y/N) [[ default: Y ]]  " RESP
   fi
   #
   RESP=${RESP^^} # convert to upper case 
   if [[ "$RESP" = "N" ]] ; then
				msg -e "${ORANGE}Skipping create_setting_mongodb${NC}"
   else
        cd $SOLUTION_HOME_DIR   
        msg "\nContinuing ... create_setting_mongodb function \n" 
        wait_with_message 15 "Let's give a bit more time for the MongoDB containers to come up " 

				msg "\n${GREEN}Configuring mongo-config-01 with /scripts/dev-init-configserver.js${NC}\n"
        docker exec -t mongo-config-01 bash -c 'mongosh < /scripts/dev-init-configserver.js'
				wait_with_message 2 ""
				#
        msg  "\n${GREEN}Configuring shard-01-node-a with /scripts/dev-init-shard01.jss${NC}\n"
        docker exec -t shard-01-node-a bash -c  'mongosh < /scripts/dev-init-shard01.js'       
				wait_with_message 2 ""
        #
				msg "\n${GREEN}Configuring shard-02-node-a with /scripts/dev-init-shard02.js${NC}\n"
        docker exec -t shard-02-node-a bash -c  'mongosh < /scripts/dev-init-shard02.js' 
				wait_with_message 2 ""
        #			
      	msg "\n${GREEN}Configuring shard-03-node-a with bash/scripts/dev-init-shard03.js${NC}\n"
        docker exec -t shard-03-node-a bash -c  'mongosh < /scripts/dev-init-shard03.js' 
				wait_with_message 60 " We need to give the cluster time to sync up"
        # 		
				msg "\n${GREEN}Configuring router-01 with /scripts/dev-init-router.js${NC}\n"
        docker exec -t router-01  bash -c  'mongosh < /scripts/dev-init-router.js'        
				wait_with_message 2 ""
        # 
				msg "\n${GREEN}Configuring mongo-config-01 with /scripts/dev-auth.js${NC}\n"
        docker exec -t mongo-config-01 bash -c  'mongosh < /scripts/dev-auth.js'  
				wait_with_message 2 ""
        #		
				msg "\n${GREEN}Configuring shard-01-node-a with /scripts/dev-auth.js${NC}\n"
        docker exec -t shard-01-node-a bash -c  'mongosh < /scripts/dev-auth.js' 	
				wait_with_message 2 ""
        #
			  msg "\n${GREEN}Configuring shard-02-node-a with /scripts/dev-auth.js${NC}\n"						
        docker exec -t shard-02-node-a bash -c  'mongosh < /scripts/dev-auth.js' 
				wait_with_message 2 ""
        #
			  msg "\n${GREEN}Configuring shard-03-node-a with /scripts/dev-auth.js${NC}\n"
        docker exec -t shard-03-node-a bash -c  'mongosh < /scripts/dev-auth.js' 
				wait_with_message 2 ""
        #  
  			msg "\n${GREEN}Deleting the file /scripts/dev-auth.js${NC}\n"
        rm -f /scripts/dev-auth.js # deleting this file because it has password information 
        #
        msg "\n${BOLD} ++++ ${NC} "
        msg "${BOLD} Because this is development & test MongoDB instance and using it for fun, NO need to send mongodb Telemetry information${NC}\n"
        #           
       	msg "\n${GREEN}Triggering off router-01 with /scripts/disableTelemetry.js${NC}"
        docker exec router-01 bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"  
        #    
        msg "\n${GREEN}Triggering off router-02 with /scripts/disableTelemetry.js${NC}"
        docker exec router-02 bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js" 
        #
				msg "\n${GREEN}Triggering off mongo-config-01 with /scripts/disableTelemetry.js${NC}"
        docker exec mongo-config-01 bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js" 
        # 
       	msg "\n${GREEN}Triggering off mongo-config-02 with /scripts/disableTelemetry.js${NC}"
        docker exec mongo-config-02 bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js" 
        #
       	msg "\n${GREEN}Triggering off mongo-config-03 with /scripts/disableTelemetry.js${NC}"
        docker exec mongo-config-03 bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"   
        #
       	msg "\n${GREEN}Triggering off shard-01-node-a with /scripts/disableTelemetry.js${NC}"
        docker exec shard-01-node-a bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"  
        #    
       	msg "\n${GREEN}Triggering off shard-01-node-b with /scripts/disableTelemetry.js${NC}"
        docker exec shard-01-node-b bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"
        # 
       	msg "${GREEN}Triggering off shard-01-node-c with /scripts/disableTelemetry.js${NC}" 
        docker exec shard-01-node-c bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"    
        #
       	msg "\n${GREEN}Triggering off shard-02-node-a with /scripts/disableTelemetry.js${NC}"
        docker exec shard-02-node-a bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"
        #
       	msg "\n${GREEN}Triggering off shard-02-node-b with /scripts/disableTelemetry.js${NC}"
        docker exec shard-02-node-b bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"  
        #
       	msg "\n${GREEN}Triggering off shard-02-node-c with /scripts/disableTelemetry.js${NC}"
        docker exec shard-02-node-c bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js" 
        #
       	msg "\n${GREEN}Triggering off shard-03-node-a with /scripts/disableTelemetry.js${NC}"
        docker exec shard-03-node-a bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"
        #
       	msg -"\n${GREEN}Triggering off shard-03-node-b with /scripts/disableTelemetry.js${NC}"       
        docker exec shard-03-node-b bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js"  
        # 
       	msg "\n${GREEN}Triggering off shard-03-node-c with /scripts/disableTelemetry.js${NC}"
        docker exec shard-03-node-c bash -c "mongosh -u $MONGODB_ADM_USER -p $MONGODB_ADM_PASSWORD </scripts/disableTelemetry.js" 
        # 
        msg "${BOLD} ++++ ${NC}\n" 
        CREATE_MONGODB_SUCCESS='Y'       
  fi
}
#######################################
# ++ function clean_mongodb
#######################################
function clean_mongodb  {

   if [[ "$SILENT" = "Y" ]] ; then 
      RESP="Y" 
   else
       msg "\nAre you sure you want to trigger this action of ==> docker compose down --rmi all --remove-orphans"
       read -r -p "Please enter your response (Y/N) [[ default: Y ]] : " RESP
    fi

   RESP=${RESP^^} # convert to upper case 
   if [[ "$RESP" = "N" ]] ; then
     msg "${ORANGE}Skipping clean_mongodb function${NC}"
   else
    if [[ -f "docker-compose.yml" ]] ; then 
	     #
		   msg "found docker-compose.yml"
		   #
		   cd "$SOLUTION_HOME_DIR"
	     docker compose down --rmi all --remove-orphans
     else
	 	   #
		   msg "Did not find docker-compose.yml, action of create_docker-compose.yml"
		   #
		   cd "$SOLUTION_HOME_DIR"
	     create_docker-compose.yml
	     docker compose down --rmi all --remove-orphans
	  fi	  
  fi
}
#######################################
# ++ function introduction_message
#######################################
function introduction_message {
      
     msg "${GREEN}+++++++++++++${NC}"
     msg "${GREEN}Solution: $VERSION ${NC}"
     msg "${BOLD}$WARNING_MESSAGE${NC}"
     msg "${GREEN}$INFORMATION_MESSAGE${NC} ${BOLD}and should not be used in PRODUCTION${NC}"
     msg "${ORANGE}SCRIPT $0 VERSION: $SCRIPT_VERSION${NC}"
      
     msg "${GREEN} This script is based on some content from - https://github.com/minhhungit/mongodb-cluster-docker-compose${NC}"
     msg "${GREEN} I modified this script to include the use of:  ${NC}"
     msg "${GREEN} - Percona Open Source MongoDB  https://www.percona.com/mongodb/software/mongodb-distribution instead on the default MongoDB CE ${NC}"
     msg "${GREEN} - Percona Monitoring and Management ${NC}"
     msg "${GREEN} - Percona Backup for MongoDB ${NC}"
      #
      #
     msg "${RED}${BOLD} Disclaimer ${NC}"
     msg "${ORANGE}    The outcome of this script is ${NC}${BOLD}NOT${NC}${ORANGE} supported by MongoDB Inc or by Percona under any of their commercial support ${NC}"
     msg "${ORANGE}    subscriptions or otherwise ${NC}"
      #
}
#######################################
# ++ function final_message
#######################################
function final_message {
 #
 msg "${CYAN}
  - MongoDB logs can be found here: $SOLUTION_HOME_DIR/mongodblogs
  - Other logs can be found here: $SOLUTION_HOME_DIR/logs for 
     - supervisord
     - pmm
     - pbm 
  ${NC}${BOLD}
 A few good MongoDB commands / functions that maybe of interest 

 using mongosh 

    - Check the Actual Runtime Parameters, db.adminCommand({ getCmdLineOpts: 1 })
    - Storage engine, db.serverStatus().storageEngine
      ${NC}"
}
#######################################
# ++ function wait_with_message
#######################################
function wait_with_message {
  #
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
    while [[ "$i" -lt "$wait_time" ]] ; do
      sleep 1
      echo -n "."
      i=$((i + 1))
    done

    
  else
    msg "Invalid input. Please enter a number."
    return 1 # Indicate an error
  fi
}
#######################################
# Show script usage info.
#######################################
usage() {
     setup_colors
     msg "\n${GREEN}Solution: $VERSION ${NC}"
     msg "${BOLD}$WARNING_MESSAGE${NC}"
     msg "${GREEN}$INFORMATION_MESSAGE${NC} ${BOLD}and should not be used in PRODUCTION${NC}"

     cat <<EOF

Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-i] [-s] [-u] [-p] [args]

Script description here.

Available options:

-h, --help          Print this help and exit
-v, --verbose       Print script debug info
-nc, --no-color     Disable colors

-i, --interactive   Run script in interactive mode
-s, --silent        Run script in silent mode, and the arguments -u and -p are mandatory 
-u, --user          MongoDB root role admin username for the this MongoDB shards instance (cluster) containerized 
-p, --password      MongoDB root role admin username password for this MongoDB shards instance (cluster) containerized 
EOF
  exit
}

#######################################
# Accept and parse script's params.
#######################################
parse_params() {
  while :; do
    case "${1-}" in
      -h | --help)
        usage
        return 0
        ;;
      -v | --verbose)
        set -x
        shift
        ;;
      -nc | --no-color)
        NO_COLOR=1
        shift
        ;;
      -i | --interactive)
         SILENT="N"
         break
        ;;   
      -s | --silent)
        SILENT="Y"
        shift # Only one shift needed for -s
        ;;
      -u | --user)
        if [[ -z "${2-}" ]]; then
          dies "Error: --user requires a value"
        fi
        INPUT_MONGODB_ADM_USERNAME="${2}"
        shift
        shift
        ;;
      -p | --password)
        if [[ -z "${2-}" ]]; then
          die "Error: --password requires a value"
        fi
        INPUT_MONGODB_ADM_PASSWORD="${2}"
        shift
        shift
        ;;
      -?*)
        die "Unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done
 
  # troubleshooting 
  #echo "parse function SILENT = $SILENT"
  #echo "parse INPUT_MONGODB_ADM_USERNAME = $INPUT_MONGODB_ADM_USERNAME"
  #echo "parse INPUT_MONGODB_ADM_PASSWORD = $INPUT_MONGODB_ADM_PASSWORD"

  #args=("$@")  # Capture any remaining positional arguments

  return 0
}
#######################################
# ++ function Main     
#######################################
main () {

  setup_colors

   # troubleshooting 
  #echo "main function SILENT = $SILENT"
  #echo "main INPUT_MONGODB_ADM_USERNAME = $INPUT_MONGODB_ADM_USERNAME"
  #echo "main INPUT_MONGODB_ADM_PASSWORD = $INPUT_MONGODB_ADM_PASSWORD"

  introduction_message 
#
  SILENT=${SILENT^^} # convert to upper case
  #
  if [[ "$SILENT" = "Y" ]] ; then 
      if [[ "$INPUT_MONGODB_ADM_USERNAME" = "" ]] ; then
            die "MongoDB root role admin username cannot be blank"
       fi

       if [[ "$INPUT_MONGODB_ADM_PASSWORD" = "" ]] ; then
           die "MongoDB root role admin username password cannot be blank"
       fi
     RESP="Y"
  else     
      msg "\nAre you sure you want to continue with this script ?"
      read -r -p "Please enter your response (Y/N) [[ default: Y ]] :" RESP
   fi
  #
  RESP=${RESP^^} # convert to upper case 
  if [[ "$RESP" = "N" ]] ; then
       msg "${CYAN}Answer was $RESP, Exiting the $0 script ${NC}" 
  else  
    # 
    if [[ -d "$SOLUTION_HOME_DIR" ]] ; then
      msg "The folder $SOLUTION_HOME_DIR exists, continuing ..."
	    msg "moving to $SOLUTION_HOME_DIR"
	    #
	    cd "$SOLUTION_HOME_DIR"
      #
      msg "-------- current folder $(pwd) ----------" 
      #
      get_mongodb_adm_user_password
      # 
	    clean_mongodb
      #
	    clean_folder
      # 
      create_docker-compose_file
      #
      create_docker_compose 
      # 
      create_setting_mongodb 
   else
     msg "${RED}****************************************************${NC}"
     msg "${RED}This folder $SOLUTION_HOME_DIR was NOT found ${NC}"
	   msg "${RED}It is imperative that this folder or mount point exist ${NC}"
     die "${RED}****************************************************${NC}"
   fi
  fi
}
#
# ======================== Start of main section ==================
if [ $# -eq 0 ]; then
  usage
  exit 1
fi
      parse_params "$@"

if main; then
   if [[ "$CREATE_MONGODB_SUCCESS" = "Y" ]] ; then 
      final_message	# Commands to execute if main returns 0
      msg "\nThe default username is ${ORANGE}$MONGODB_ADM_USER${NC} and the password is ${ORANGE}$MONGODB_ADM_PASSWORD${NC} for this MongoDB shards cluster"
   fi   
else 
   ida "${RED} Hmm! something happened. and the script did not execute successfully${NC}"
fi
# ======================== end of main section ==================