#|/bin/bash

otsdb_port=4242
MAPR_HOME=${MAPR_HOME:-/opt/mapr}

read -p 'Container user: ' user
read -s -p 'Enter password: ' passw
echo \

# Get the cluster name
if [ -f $MAPR_HOME/conf/mapr-clusters/conf ]; then
    # get the first cluster name listed in the mapr-clusters.conf
    cluster=$(head -1 /opt/mapr/conf/mapr-clusters.conf | cut -f 1 -d " ")
    echo 'We appear to be running on a node of cluster: $cluster'
else
    read -p 'Cluster name: ' cluster
fi

# Get the list of CLDB and Zookeeper nodes
if [ -f $MAPR_HOME/bin/maprcli ]; then
    cldbs=$(maprcli node listcldbs)
    echo 'Discovered these CLDBs for cluster $cluster:  $cldbs'
    zkeepers=$(maprcli node listzookeepers)
    echo 'Zookeeper hosts:  $zkeepers'
else
    read -p 'List of CLDBs: ' cldbs
    read -p 'List of Zookeeper nodes: ' zkeepers
    echo ''
fi

docker_args="-p 4242:$otsdb_port \
             -e MAPR_CLUSTER=$cluster \
               -e MAPR_CLDB_HOSTS=$cldbs \
               -e MAPR_ZK_HOSTS=$zkeepers \
             -e MAPR_CONTAINER_USER=$user \
             -e MAPR_CONTAINER_PASSWORD=$passw \
             -e MAPR_CONTAINER_GROUP=$user \
             -e MAPR_CONTAINER_UID=$(id -u $user) \
             -e MAPR_CONTAINER_GID=$(id -g $user) \
             -e MAPR_MOUNT_PATH=/mapr \
               --cap-add SYS_ADMIN \
               --cap-add SYS_RESOURCE \
               --device /dev/fuse"

# Refresh the MapR service ticket
if [ -f $MAPR_HOME/bin/maprlogin ]; then
    echo 'Generating service ticket...'
    ticket_path=/tmp/maprserviceticket_dsr_$user
    if [ -f $ticket_path ]; then
        sudo rm -rf $ticket_path
    fi
    maprlogin generateticket \
        -user $user \
        -type service \
        -out $ticket_path \
        -duration 365:0:0 \
        -renewal 730:0:0
    sudo chown $user:$user $ticket_path
    docker_args=$docker_args \
		  -e MAPR_TICKETFILE_LOCATION=/tmp/maprticket \
                  -v $ticket_path:/tmp/maprticket:ro
else
    echo "The 'maprlogin' command is not availabe on this host; a MapR ticket could not be created."
    echo 'Defaulting to non-secure mode.'
fi

# Start the container
echo 'Starting PACC docker container...'
sudo docker run -it $docker_args $1
