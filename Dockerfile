FROM middleware-docker-local-release.artifactory.cib.echonet/mdw-openjdk-temurin-11-alpine-cib:v3.23

ARG TOMCAT_VERSION=10.1.57

ENV CATALINA_HOME=/opt/tomcat
ENV CATALINA_BASE=/opt/tomcat
ENV PATH="${CATALINA_HOME}/bin:${PATH}"

RUN apk add --no-cache curl tar

RUN mkdir -p "${CATALINA_HOME}" \
    && curl -fsSL \
       "https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
       -o /tmp/tomcat.tar.gz \
    && tar -xzf /tmp/tomcat.tar.gz \
       -C "${CATALINA_HOME}" \
       --strip-components=1 \
    && rm -f /tmp/tomcat.tar.gz

RUN rm -rf \
    "${CATALINA_HOME}/webapps/docs" \
    "${CATALINA_HOME}/webapps/examples" \
    "${CATALINA_HOME}/webapps/host-manager" \
    "${CATALINA_HOME}/webapps/manager" \
    "${CATALINA_HOME}/webapps/ROOT"

COPY ROOT/ "${CATALINA_HOME}/webapps/ROOT/"

RUN chgrp -R 0 "${CATALINA_HOME}" \
    && chmod -R g=u "${CATALINA_HOME}"

WORKDIR "${CATALINA_HOME}"

EXPOSE 8080

CMD ["catalina.sh", "run"]  