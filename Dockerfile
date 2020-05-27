# Stage 1: build the opentsdb.tsuid.ratelimiter plugin .jar, using a generic jdk base image
FROM openjdk:8-jdk-alpine3.7 AS builder

#ARG http_proxy=http://interneta:8080
#ARG https_proxy=http://interneta:8080

RUN java -version
COPY ./opentsdb-tsuid-ratelimiter /usr/src/opentsdb-tsuid-ratelimiter
WORKDIR /usr/src/opentsdb-tsuid-ratelimiter
RUN apk --no-cache --allow-untrusted add maven && mvn --version
RUN mvn package
#RUN mvn package -Dhttp.proxyHost=interneta -Dhttp.proxyPort=8080 -Dhttps.proxyHost=interneta -Dhttps.proxyPort=8080


# Use the custom MapR PACC from neilcedwards - it needs to be custom because we need Hbase client included.
FROM neilcedwards/pacc-custom:601_500_yarn_fuse_hbase_streams

#ARG http_proxy=http://interneta:8080
#ARG https_proxy=https://interneta:8080

# These environment variables are associated with the OpenTSDB configuration, and can be overridden at run time
ENV MAPR_HOME=/opt/mapr \
    LD_LIBRARY_PATH=$MAPR_HOME/lib \
    JVM_START_MEM=256m \
    JVM_MAX_MEM=1g \
    MAPR_HOME=/opt/mapr \
    OT_TSD_o_CORE_o_ENABLE_o_UI=false \
    OT_TSD_o_DEFAULT_o_USESTREAMS=false

# Install the latest  OpenTSDB from the MapR repo
RUN yum -y update && \
    yum -y install gnuplot mapr-opentsdb && \
    yum -y install python-pip python-devel gcc && \
    yum -y install nmap-ncat && \
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
ADD ./tcollector_opentsdb.sh /tmp/tcollector_opentsdb.sh
RUN sudo chown 1000:100 /tmp/tcollector_opentsdb.sh; \
    sudo chmod a+rx /tmp/tcollector_opentsdb.sh

# Copy the opentsdb.tsuid.ratelimiter plugin jar from our Step 1 build
COPY --from=builder /usr/src/opentsdb-tsuid-ratelimiter/target/tsuid-ratelimiter-plugin-1.1-SNAPSHOT.jar /tmp
RUN OTSDB_HOME="/opt/mapr/opentsdb/opentsdb-$(</opt/mapr/opentsdb/opentsdbversion)"; \
    sudo mv /tmp//tsuid-ratelimiter-plugin-1.1-SNAPSHOT.jar ${OTSDB_HOME}/share/opentsdb/plugins

ENV LD_LIBRARY_PATH=${MAPR_HOME}/lib
RUN echo LD_LIBRARY_PATH = $LD_LIBRARY_PATH

HEALTHCHECK --interval=5s --timeout=3s --start-period=240s CMD curl --fail http://localhost:4242/api/version || exit 1

EXPOSE 4242/tcp

# Finally, start the TSD.
CMD [ "/tmp/run.sh" ]

