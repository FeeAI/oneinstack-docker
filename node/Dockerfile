ARG NODE_VERSION=24
ARG NODE_BASE_IMAGE=node:${NODE_VERSION}-alpine
FROM ${NODE_BASE_IMAGE}

ARG APP_UID=1000
ARG APP_GID=1000

LABEL org.opencontainers.image.title="OneinStack Node.js"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then apk add --no-cache shadow; fi; \
    if [ "$(id -g node)" != "${APP_GID}" ]; then groupmod -o -g "${APP_GID}" node; fi; \
    if [ "$(id -u node)" != "${APP_UID}" ]; then usermod -o -u "${APP_UID}" -g "${APP_GID}" node; fi

COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
RUN chmod 0755 /usr/local/bin/oneinstack-secrets-entrypoint

USER node
WORKDIR /var/www/html

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
CMD ["sleep", "infinity"]
