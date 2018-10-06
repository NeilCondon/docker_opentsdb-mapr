#/bin/bash
#
# Copyright (c) 2018 & onwards.  Edwards Limited, All rights reserverd.
#
# This script configures the container's OpenTSDB instance by adjusting a config
# file based on environment variable settings.
#

MAPR_HOME=${MAPR_HOME:-/opt/mapr}
OTSDB_HOME="${OTSDB_HOME:-/opt/mapr/opentsdb/opentsdb-$(</opt/mapr/opentsdb/opentsdbversion)}"
OTSDB_CONF_FILE="${OTSDB_HOME}/etc/opentsdb/opentsdb.conf"
JVMARGS="-enableassertions -enablesystemassertions -Xms$JVM_START_MEM -Xmx$JVM_MAX_MEM"


#####################################################################################
# Function that generlaises replacement of a configuration entry in the file
#####################################################################################
function replace_or_add_configOption () {
    local config=$1
    local value=$2
    local file=$3
    local after=$4

    # Replace using sed (this will fail if the config isn't present)
    sed -i "s/.*$config.*/$config = $value/g" $file

    # grep for the config.   If it's not found, add it after the first line containing the matching string.
    grep -q "$config" $file || sed -i "0,/^$after\+/s//\0\n$config = $value/" $file
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
#  - we will use 'sed' and replace an entire matching line with the setting we want.

###################################
# The 'tsd.core' settings:
replace_or_add_configOption "tsd.core.auto_create_metrics" "true" $OTSDB_CONF_FILE "tsd.core."
replace_or_add_configOption "tsd.core.meta.enable_realtime_uid" "true" $OTSDB_CONF_FILE "tsd.core."
replace_or_add_configOption "tsd.core.meta.enable_realtime_ts" "false" $OTSDB_CONF_FILE "tsd.core."
replace_or_add_configOption "tsd.core.meta.enable_tsuid_tracking" "false" $OTSDB_CONF_FILE "tsd.core."
replace_or_add_configOption "tsd.core.tree.enable_processing" "true" $OTSDB_CONF_FILE "tsd.core."
replace_or_add_configOption "tsd.core.enable_ui" "true" $OTSDB_CONF_FILE "tsd.core."
relpace_or_add_configOption "tsd.storage.hbase.zk_quorum" "eddisc0:5181" $OTSDB_CONF_FILE "tsd.storage."

###################################
# The REQUIRED tsd.http settings:
replace_or_add_configOption "tsd.http.staticroot" $OTSDB_HOME/share/opentsdb/static/ $OTSDB_CONF_FILE "tsd.http."
replace_or_add_configOption "tsd.http.cachedir" $OTSDB_HOME/var/cache/opentsdb $OTSDB_CONF_FILE "tsd.http."


###################################
# The table locations
replace_or_add_configOption "tsd.storage.hbase.data_table" $TSDB_TABLE_PATH $OTSDB_CONF_FILE "tsd.storage."
replace_or_add_configOption "tsd.storage.hbase.uid_table" $UID_TABLE_PATH $OTSDB_CONF_FILE "tsd.storage."
replace_or_add_configOption "tsd.storage.hbase.meta_table" $META_TABLE_PATH $OTSDB_CONF_FILE "tsd.storage."
replace_or_add_configOption "tsd.storage.hbase.tree_table" $TREE_TABLE_PATH $OTSDB_CONF_FILE "tsd.storage.hbase."

###################################
# The MapR-ES (streams) parameters
replace_or_add_configOption "tsd.default.usestreams" $OTSDB_CONSUME_DIRECT $OTSDB_CONF_FILE "tsd.default."
# set stream options if usestrems is true, with TSD as read-only; else TSD is read-write
if [$OTSDB_CONSUME_DIRECT = true]; then
    replace_or_add_configOption "tsd.default.consumergroup" $STREAMS_CONSUMER_GROUP $OTSDB_CONF_FILE "tsd.default."
    replace_or_add_configOption "tsd.streams.path" $STREAM_PATH $OTSDB_CONF_FILE "tsd.default."
    replace_or_add_configOption "tsd.streams.consumer.memory" $STREAMS_CONSUMER_MEMORY $OTSDB_CONF_FILE "tsd.default."
    replace_or_add_configOption "tsd.streams.count" $STREAMS_COUNT $OTSDB_CONF_FILE "tsd.default."
    replace_or_add_configOption "tsd.streams.autocommit.interval" $STREAMS_AUTOCOMMING_INTERVAL $OTSDB_CONF_FILE "tsd.default."
    replace_or_add_configOption "tsd.mode" "ro" $OTSDB_CONF_FILE "tsd.default."
else
    replace_or_add_configOption "tsd.mode" "rw" $OTSDB_CONF_FILE "tsd.default."
fi


##################################
# Additional arbitrary environment variables.
#  - Thesea are prefixed 'OT_'
#  - '_dot_' in variable names will be replaced with '.'
#  - varaibles can be specified to overwrite anything in the conf file
#
for VAR in $(env | grep 'OT_' | sed -r "s/([^=]*).*/\1/g"); do
    CONFIG_NAME=$(echo ${VAR:3} | tr '_dot_' '.' | tr '[:upper:]' '[:lower:]')
    CONFIG_VALUE=$(eval echo \$$VAR)
    replace_or_add_configOption $CONFIG_NAME $CONFIG_VALUE $OTSDB_CONF_FILE "tsd.default."
done


#####################################################################################
# Start the TSD
#####################################################################################
tsdb tsd
