FROM debian:13

ARG TOMCAT_VERSION=10.1.55

ENV DEBIAN_FRONTEND=noninteractive
ENV CATALINA_HOME=/opt/tomcat
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${CATALINA_HOME}/bin:${JAVA_HOME}/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-21-jre-headless \
        curl \
        ca-certificates \
        tar && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt && \
    curl -fsSL \
        "https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
        -o /tmp/tomcat.tar.gz && \
    tar -xzf /tmp/tomcat.tar.gz -C /opt && \
    mv "/opt/apache-tomcat-${TOMCAT_VERSION}" "${CATALINA_HOME}" && \
    rm /tmp/tomcat.tar.gz

RUN rm -rf \
    "${CATALINA_HOME}/webapps/docs" \
    "${CATALINA_HOME}/webapps/examples" \
    "${CATALINA_HOME}/webapps/host-manager" \
    "${CATALINA_HOME}/webapps/manager"

WORKDIR ${CATALINA_HOME}

EXPOSE 8080

CMD ["catalina.sh", "run"]




root@ub24nginx:~# docker images
IMAGE                ID             DISK USAGE   CONTENT SIZE   EXTRA
alpine-tomcat10:v2   389145c1fc61        239MB             0B    U
debian13:v2          ebb392836c73        368MB             0B    U



############################
###### Alpine version ######
############################
FROM alpine:3.24

ARG TOMCAT_VERSION=10.1.57

ENV CATALINA_HOME=/opt/tomcat
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk
ENV PATH=$CATALINA_HOME/bin:$JAVA_HOME/bin:$PATH

RUN apk add --no-cache \
    openjdk21-jre-headless \
    ca-certificates \
    tzdata \
    wget \
    tar

RUN addgroup -S tomcat && \
    adduser -S -G tomcat tomcat

RUN mkdir -p $CATALINA_HOME && \
    wget https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tar.gz && \
    tar -xzf /tmp/tomcat.tar.gz --strip-components=1 -C $CATALINA_HOME && \
    rm /tmp/tomcat.tar.gz && \
    rm -rf \
        $CATALINA_HOME/webapps/docs \
        $CATALINA_HOME/webapps/examples \
        $CATALINA_HOME/webapps/host-manager \
        $CATALINA_HOME/webapps/manager

RUN chown -R tomcat:tomcat $CATALINA_HOME

WORKDIR $CATALINA_HOME

USER tomcat

EXPOSE 8080

CMD ["catalina.sh","run"]