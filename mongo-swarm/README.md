Docker Swarm image for Mongo replicated cluster.

This image will automatically create a Mongo Replication Set Cluster in Docker Swarm with automatic failover.


It supports scale up and scale down, the cluster will be automatically reconfigured.

Build:

```docker build -t mongo:3.2-swarm```

Persistence:

```docker volume create --name mongo```

To create the cluster:

```docker service create --name mongo --network rocketnet --endpoint-mode dnsrr --replicas 3 --stop-grace-period 60s --mount type=volume,source=mongo,target=/data/db mongo:3.2-swarm```

```docker service create --name mongo-arb --network rocketnet --endpoint-mode dnsrr --env "ARBITER=true" mongo:3.2-swarm```
