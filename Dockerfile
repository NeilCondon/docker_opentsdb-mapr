# Use the custom MapR PACC from neilcedwards - it needs to be custom because we need Hbase client included.
FROM neilcedwards/opentsdb-mapr:pacc_6.0.1_5.0.0_yarn_fuse_hbase_streams

# These environment variables are associated with the OpenTSDB configuration, and can be overridden at run time
ENV MAPR_HOME=/opt/mapr \
    LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$MAPR_HOME/lib} \
    JVM_START_MEM=256m \
    JVM_MAX_MEM=1g \
    MAPR_HOME=/opt/mapr \
    OT_TSD_o_CORE_o_ENABLE_o_UI=false \
    OT_TSD_o_DEFAULT_o_USESTREAMS=false

# Install the latest  OpenTSDB from the MapR repo
RUN yum -y update && \
    yum -y install mapr-opentsdb && \
    yum -y install python-pip python-devel gcc && \
    yum clean all && \
    pip install --upgrade pip && \
    pip install --global-option=build_ext --global-option="--library-dirs=/opt/mapr/lib" --global-option="--include-dirs=/opt/mapr/include/" mapr-streams-python

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

