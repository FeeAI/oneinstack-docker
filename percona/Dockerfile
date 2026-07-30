ARG PERCONA_VERSION=8.4
FROM percona/percona-server:${PERCONA_VERSION}

LABEL org.opencontainers.image.title="OneinStack Percona Server"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

USER root

COPY conf.d/oneinstack.cnf /etc/my.cnf.d/oneinstack.cnf
COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN set -eux; \
    microdnf install -y util-linux-core; \
    microdnf clean all; \
    chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
