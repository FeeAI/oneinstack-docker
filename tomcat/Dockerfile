ARG TOMCAT_VERSION=11.0
ARG JDK_VERSION=25
FROM tomcat:${TOMCAT_VERSION}-jdk${JDK_VERSION}-temurin

LABEL org.opencontainers.image.title="OneinStack Tomcat"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

RUN set -eux; \
    rm -rf /usr/local/tomcat/webapps/*; \
    if [ -d /usr/local/tomcat/webapps.dist/ROOT ]; then \
      cp -a /usr/local/tomcat/webapps.dist/ROOT /usr/local/tomcat/webapps/ROOT; \
    fi

COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

EXPOSE 8080

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
