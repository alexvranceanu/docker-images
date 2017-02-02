#!/bin/bash

# Load variables and functions
source functions.sh

# Load all the replicas of this service
load_replicas

# Check which of the current replicas is the master
export master=$(get_master)
if [ -z "${master}" ]; then
	export master=${main_replica_ip}
fi

# Create data directories and set up permissions
mkdir -p /data/db/${this_replica_number}
chown -R mongodb:mongodb /data/db

# On service scale down, gracefully remove this node from the replication set and stop mongod
trap '/mongo-shutdown.sh' SIGTERM

# Check if this is supposed to be an arbiter
if [ "${ARBITER}" == "true"  ]; then
	exec gosu mongodb mongod --smallfiles --oplogSize 128 --replSet "${REPLICA_SET}" "$@" &
	sleep 5
        # Keep trying to connect this replica to the replication set (as it may disconnect)
        while true; do
                # Check if this container is already in the replication set
                if [ "$(mongo ${master}/${MONGO_DATABASE} --eval 'rs.conf()' | grep -o ${this_replica_hostname})" != "${this_replica_hostname}" ]; then
                        debug_log "Adding arbiter..."
                        status=$(mongo ${master}/${MONGO_DATABASE} --quiet --eval "rs.addArb(\"${this_replica_hostname}\")")
                        if [ "$?" -ne "0" ]; then
                                debug_log "Arbiter addition failed, trying again in 30 seconds..."
                        fi
                fi
                sleep 30;
                load_replicas
                export master=$(get_master)
        done &
        wait $(pidof mongod)
fi


# Check if this is the first replica, set it up as primary if one doesn't already exist in the cluster
if [ "${this_replica_number}" -eq "1"  ]; then
	exec gosu mongodb mongod --smallfiles --oplogSize 128 --replSet "${REPLICA_SET}" --dbpath /data/db/${this_replica_number} "$@" &
	sleep 5;

	load_replicas
	master=$(get_master)
	if [ -z "${master}" ]; then

		# Initiate the replication set
		debug_log "Initializing replication set..."
		mongo ${this_replica_hostname}/${MONGO_DATABASE} --eval "rs.initiate({ _id: '${REPLICA_SET}', members: [ { _id: 0, host: '${this_replica_hostname}:27017', priority: 1000 } ]})"

		# If this replica set was initialized in the past the above command will fail and we need to re-initialize
		mongo --eval "cfg=rs.conf(); cfg.members.splice(0,50); cfg.members.push({_id: 0, host: '${this_replica_hostname}:27017', priority: 1000}); rs.reconfig(cfg,{force: true});"
	else
		# Background thread to connect to the existing primary replica
		connect_to_master &
	fi

# This is not the first replica, so we need to connect to master
else
	exec gosu mongodb mongod --smallfiles --oplogSize 128 --replSet "${REPLICA_SET}" --dbpath /data/db/${this_replica_number} "$@" &

	# Sleep longer to allow the primary to initialize
	sleep 30

	# Background thread to connect to the existing primary replica
	connect_to_master &

fi

# Required for Docker
wait $(pidof mongod)
