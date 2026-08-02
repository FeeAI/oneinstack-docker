ARG POSTGRES_VERSION=18
ARG POSTGRES_BASE_IMAGE=postgres:${POSTGRES_VERSION}-alpine
FROM ${POSTGRES_BASE_IMAGE}

LABEL org.opencontainers.image.title="OneinStack PostgreSQL"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY initdb /docker-entrypoint-initdb.d
COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
