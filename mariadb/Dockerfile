ARG MARIADB_VERSION=10.11
FROM mariadb:${MARIADB_VERSION}

LABEL org.opencontainers.image.title="OneinStack MariaDB"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY conf.d/oneinstack.cnf /etc/mysql/conf.d/oneinstack.cnf
COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
