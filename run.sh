#!/bin/bash
#
# Copyright (c) 2018 & onwards.  Edwards Limited, All rights reserverd.
#
# This script configures the container's OpenTSDB instance by adjusting a config
# file based on runtime environment variable settings.
#

# Some preliminary variables.   Some will have been set in the Dockerfile.
export MAPR_HOME=${MAPR_HOME:-/opt/mapr}
export OTSDB_HOME="${OTSDB_HOME:-/opt/mapr/opentsdb/opentsdb-$(</opt/mapr/opentsdb/opentsdbversion)}"
export OTSDB_CONF_FILE="${OTSDB_HOME}/etc/opentsdb/opentsdb.conf"
export MAPR_ZK_HOSTS="${MAPR_ZK_HOSTS:-$(maprcli node listzookeepers)}"
export JVMARGS="-enableassertions -enablesystemassertions -Xms$JVM_START_MEM -Xmx$JVM_MAX_MEM"

# the MAPR_CONTAINER_USER and MAPR_CLUSTER are only known at runtime, so the table paths cannot be set until runtime
export TSDB_TABLES_ROOT=/mapr/${MAPR_CLUSTER}/user/${MAPR_CONTAINER_USER}/opentsdb-default \
export OT_TSD_o_STORAGE_o_HBASE_o_DATA_TABLE=${TSDB_TABLES_ROOT}/tsdb \
export OT_TSD_o_STORAGE_o_HBASE_o_META_TABLE=${TSDB_TABLES_ROOT}/tsdb-meta \
export OT_TSD_o_STORAGE_o_HBASE_o_UID_TABLE=${TSDB_TABLES_ROOT}/tsdb-uid \
export OT_TSD_o_STORAGE_o_HBASE_o_TREE_TABLE=${TSDB_TABLES_ROOT}/tsdb-tree


#####################################################################################
# Function that generlaises replacement of a configuration entry in the file
#  - we will use 'sed' and replace an entire matching line with the setting we want.
#####################################################################################
function replace_or_add_configOption () {
    local config=$1
    local value=$2
    local file=$3
    local after=$4

    # Replace using sed (this will fail if the config isn't present)
    echo "Setting $config = $value in $file."
    sed -i "s|.*$config.*|$config = $value|g" $file

    # grep for the config.   If it's not found, add it after the first line containing the matching string.
    # grep -q "$config" $file || sed -i "0,/^$after\+/s//\0\n$config = $value/" $file
}


#####################################################################################
# Create Hbase tables using the table paths specified at container launch
#####################################################################################
exec "hbase" shell <<EOF
create '$UID_TABLE_PATH',
  {NAME => 'id', COMPRESSION => 'LZO', BLOOMFILTER => 'ROW'},
  {NAME => 'name', COMPRESSION => 'LZO', BLOOMFILTER => 'ROW'}

create '$TSDB_TABLE_PATH',
  {NAME => 't', VERSIONS => 1, COMPRESSION => 'LZO', BLOOMFILTER => 'ROW'}

create '$TREE_TABLE_PATH',
  {NAME => 't', VERSIONS => 1, COMPRESSION => 'LZO', BLOOMFILTER => 'ROW'}

create '$META_TABLE_PATH',
  {NAME => 'name', COMPRESSION => 'LZO', BLOOMFILTER => 'ROW'}
EOF


#####################################################################################
# Take ownership of the OpenTSDB files
#####################################################################################
sudo chown -R "$MAPR_CONTAINER_USER":"$MAPR_CONTAINER_GROUP" $OTSDB_HOME


#####################################################################################
# Modify the opentsdb.conf file using the parameters specified at container launch.
#####################################################################################
###################################
# The 'tsd.core' settings:
replace_or_add_configOption "tsd.storage.hbase.zk_quorum" $MAPR_ZK_HOSTS $OTSDB_CONF_FILE "tsd.storage."

###################################
# The REQUIRED tsd.http settings:
replace_or_add_configOption "tsd.http.staticroot" $OTSDB_HOME/share/opentsdb/static $OTSDB_CONF_FILE "tsd.http."
replace_or_add_configOption "tsd.http.cachedir" $OTSDB_HOME/var/cache/opentsdb $OTSDB_CONF_FILE "tsd.http."

##################################
# Additional arbitrary environment variables.
#  - Thesea are prefixed 'OT_'
#  - '_o_' in variable names will be replaced with '.'
#  - varaibles can be specified to overwrite anything in the conf file
#
for VAR in $(env | grep 'OT_' | sed -r "s/([^=]*).*/\1/g"); do
    CONFIG_NAME=$(echo ${VAR:3} | sed 's/_o_/./g' | tr '[:upper:]' '[:lower:]')
    CONFIG_VALUE=$(eval echo \$$VAR)
    replace_or_add_configOption $CONFIG_NAME $CONFIG_VALUE $OTSDB_CONF_FILE "tsd.default."
done


#####################################################################################
# Start the TSD
#####################################################################################
tsdb tsd
