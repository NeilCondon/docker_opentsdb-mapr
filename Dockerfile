# Use the custom MapR PACC from neilcedwards - it needs to be custom because we need Hbase client included.
FROM neilcedwards/opentsdb-mapr:pacc_6.0.1_5.0.0_yarn_fuse_hbase_streams

# These environment variables are associated with the OpenTSDB configuration, and can be overridden at run time
ENV OT_TSD_o_CORE_o_ENABLE_o_UI=false \
    OT_TSD_o_DEFAULT_o_USESTREAMS=false \
    TSDB_TABLES_ROOT=/mapr/user/${MAPR_CONTAINER_USER}/opentsdb-default \
    OT_TSD_o_STORAGE_o_HBASE_o_DATA_TABLE=${TSDB_TABLES_ROOT}/tsdb \
    OT_TSD_o_STORAGE_o_HBASE_o_META_TABLE=${TSDB_TABLES_ROOT}/tsdb-meta \ 
    OT_TSD_o_STORAGE_o_HBASE_o_UID_TABLE=${TSDB_TABLES_ROOT}/tsdb-uid \
    OT_TSD_o_STORAGE_o_HBASE_o_TREE_TABLE=${TSDB_TABLES_ROOT}/tsdb-tree \
    JVM_START_MEM=100k \
    JVM_MAX_MEM=1g \
    MAPR_HOME=/opt/mapr

# Install the latest  OpenTSDB from the MapR repo
RUN yum -y update && \
    yum -y install mapr-opentsdb

# Copy asynchbase jar
RUN OTSDB_HOME="/opt/mapr/opentsdb/opentsdb-$(</opt/mapr/opentsdb/opentsdbversion)"; \
    ASYNCVER=1.7; \
    asyncHbaseJar=""; \
    jar_ver=""; \
    rc=1; \
    asyncHbaseJar=$(find ${MAPR_HOME}/asynchbase -name 'asynchbase*mapr*.jar' | fgrep -v javadoc|fgrep -v sources); \
    if [ -n "$asyncHbaseJar" ]; then \
        jar_ver=$(basename $asyncHbaseJar); \
        jar_ver=$(echo $jar_ver | cut -d- -f2); \
        if [ -n "$jar_ver" ]; then \
            verify_ver=$(echo $jar_ver | cut -d. -f1,2); \
            # verify the two most significant; \
            if [ -n "$verify_ver" -a "$verify_ver" = "$ASYNCVER" ]; then \
                sudo cp  "$asyncHbaseJar" ${OTSDB_HOME}/share/opentsdb/lib/asynchbase-"$jar_ver".jar; \
                rc=$?; \
            else \ 
                logErr "Incompatible asynchbase jar found"; \
            fi; \
        fi; \
    fi

# Copy the run.sh script, which will modify opentsdb.conf at container run-time, into the /tmp folder
ADD ./run.sh /tmp/run.sh
RUN sudo chown 1000:100 /tmp/run.sh; \
    sudo chmod a+rx /tmp/run.sh
ADD ./opentsdb.conf.new /tmp/opentsdb.conf
RUN sudo chown 1000:100 /tmp/opentsdb.conf; \
    OTSDB_HOME="/opt/mapr/opentsdb/opentsdb-$(</opt/mapr/opentsdb/opentsdbversion)"; \
    sudo mv ${OTSDB_HOME}/etc/opentsdb/opentsdb.conf ${OTSDB_HOME}/etc/opentsdb/opentsdb.conf.original; \
    sudo mv /tmp/opentsdb.conf ${OTSDB_HOME}/etc/opentsdb/opentsdb.conf

EXPOSE 4242/tcp

# Finally, start the TSD.
#ENTRYPOINT [ "/tmp/run.sh" ]

