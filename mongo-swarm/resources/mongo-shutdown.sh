#!/bin/bash

# Set the shutdown lock
touch /var/run/lock/mongo-shutdown.lock

# Load variables and functions
source functions.sh

debug_log "MongoDB Shutdown initiated"

# Make this member not eligible for PRIMARY election (in case multiple nodes are being shut down and this one is elected primary)
mongo --quiet --eval 'rs.freeze(300)'

# Load variables and functions
source functions.sh

# Load all the replicas of this service
load_replicas

# Check which of the current replicas is the master
export master=$(get_master)
if [ -z "${master}" ]; then
        export master="${main_replica_ip}:27017"
fi
debug_log "Master detected: ${master}"

# Set the delay before starting the shutdown process
((sleep_time=$this_replica_number*3))
sleep $sleep_time

# If this is the PRIMARY we need to make it SECONDARY, then remove it from replication and shutdown
if [ "${master}" == "$(hostname):27017" ]; then
        if [ "${#replicas[@]}" -gt 1 ]; then
		mongo --quiet --eval "rs.stepDown()"
		sleep 2
		# This replica has stepped down, check if there is a new primary
		load_replicas
		new_master="localhost"
		new_master=$(get_master)
		# Keep trying to find a master, until an election took place
		while [ -z "${new_master}" ]; do
			debug_log "New Master not detected, retrying..."
			new_master=$(get_master)
			sleep 2
		done
		debug_log "New Master detected: ${new_master}"
        	mongo ${new_master}/${MONGO_DATABASE} --quiet --eval "rs.remove(\"${this_replica_hostname}:27017\")"
	else
		debug_log "Last replica, shutting down now."
	fi

# If this is the SECONDARY replica, remove it from the replication set and shutdown
else
	# Sleep to allow other replicas to shutdown if multiple ones are shutting down
	sleep $sleep_time
	# Refresh the replicas
	load_replicas
	new_master="localhost"
        if [ "${#replicas[@]}" -gt 1 ]; then
                new_master=$(get_master)
                # Keep trying to find a master, until an election took place
                while [ -z "${new_master}" ]; do
                        debug_log "New Master not detected, retrying..."
                        new_master=$(get_master)
                        sleep 2
                done
                debug_log "New Master detected: ${new_master}"
        fi
	mongo ${new_master}/${MONGO_DATABASE} --quiet --eval "rs.remove(\"${this_replica_hostname}:27017\")"
fi

# Finally, send SIGTERM to mongod
#kill $(pidof mongod)
mongo --quiet --eval 'db.adminCommand("shutdown")'
