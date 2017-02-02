#!/bin/bash
# Required environment variables and defaults
REPLICA_SET=${REPLICA_SET:-rs0}
MONGO_DATABASE=${MONGO_DATABASE:-rocketchat}
ARBITER=${ARBITER:-false}
ARBITER_FOR=${ARBITER_FOR:-mongo}
DEBUG=${DEBUG:-true}

# Logging function
function debug_log(){
        if [ "${DEBUG}" == "true" ] && [ ! -z "$1" ]; then
                echo "DEBUG: $1" >&2
        fi
}

###### Grab information about the current service
if [ "${ARBITER}" == "false"  ]; then
	service_name=$(nslookup `hostname` | grep Address | tail -n 1 | awk '{print $2}' | xargs nslookup | grep name | awk '{print $4}' | cut -d\. -f1)
	debug_log "Service name: ${service_name}"
else
	service_name=${ARBITER_FOR}
fi

# Global array for all replicas
declare -a replicas

# Function to fetch all replicas
function load_replicas(){
	# Get the list of IPs from all containers
	replicas_ips=$(nslookup $service_name | grep "Address: \d*" | awk '{print $2}'| IFS=' ' xargs echo )
	IFS=' ' read -r -a replica_list  <<< "${replicas_ips}"

	# Create an array based on the replica number (replicas[1]=IP_ADDRESS_OF_REPLICA_1)
	for element in "${replica_list[@]}"; do
		replica_number=$(nslookup $element | grep name | awk '{print $4}' | cut -d\. -f2)
		debug_log  "Replica number for ${element}: ${replica_number}"
		replicas[$replica_number]=$element
	done

	# Set a few variables for easier usage
	export main_replica_ip="${replicas[1]}"
	export this_replica_number=$(nslookup `hostname` | grep Address | tail -n 1 | awk '{print $2}' | xargs nslookup | grep name | awk '{print $4}' | cut -d\. -f2)
	export this_replica_ip=$(nslookup `hostname` | grep Address | tail -n 1 | awk '{print $2}')
	export this_replica_hostname=$(hostname)
}

# Function to print the primary replica in the replication set
function get_master(){
	primary=""
	debug_log "Checking replicas ${replicas[@]}"
	for element in "${replicas[@]}"; do
		debug_log "Checking if replica ${element} is primary..."
		status=$(mongo ${element}/${MONGO_DATABASE} --quiet --eval 'rs.isMaster().primary')
		debug_log "Response from ${element}: ${status}"
		if [ "$?" -eq "0" ] && [ ! -z "${status}" ]; then
			primary="${status}"
		fi
	done
	debug_log "Determined primary: ${primary}"
	echo "${primary}"
}

# Function to add current replica to the replication set
function connect_to_master(){
    # Keep trying to connect this replica to the replication set (as it may disconnect)
    while [ ! -f /var/run/lock/mongo-shutdown.lock ]; do
            # Check if this container is already in the replication set
            if [ "$(mongo ${master}/${MONGO_DATABASE} --eval 'rs.conf()' | grep -o ${this_replica_hostname} | tail -n1)" != "${this_replica_hostname}" ]; then
                    debug_log "Joining replication set on ${master}..."
                    status=$(mongo ${master}/${MONGO_DATABASE} --quiet --eval "rs.add({ host: \"${this_replica_hostname}\", priority: $this_replica_number})")
                    if [ "$?" -ne "0" ]; then
                            debug_log "Replication set join failed, trying again in 60 seconds..."
                    fi
            fi
            sleep 60
            load_replicas
            export master=$(get_master)
	    debug_log "Detected PRIMARY: ${master}"
     done
}
