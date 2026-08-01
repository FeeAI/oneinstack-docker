ARG REDIS_VERSION=8.8
ARG REDIS_BASE_IMAGE=redis:${REDIS_VERSION}-alpine
FROM ${REDIS_BASE_IMAGE}

LABEL org.opencontainers.image.title="OneinStack Redis"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY redis.conf /usr/local/etc/redis/redis.conf

EXPOSE 6379
