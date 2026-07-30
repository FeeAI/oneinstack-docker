ARG MONGODB_VERSION=8.0
FROM mongo:${MONGODB_VERSION}

LABEL org.opencontainers.image.title="OneinStack MongoDB"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY initdb /docker-entrypoint-initdb.d
COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
