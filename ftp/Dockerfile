FROM alpine:3.24

ARG APP_UID=1000
ARG APP_GID=1000

LABEL org.opencontainers.image.title="OneinStack Pure-FTPd"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

RUN set -eux; \
    apk add --no-cache openssl pure-ftpd shadow; \
    addgroup -g 2001 ftpgroup; \
    adduser -D -H -u 2001 -G ftpgroup -s /sbin/nologin ftpuser; \
    groupmod -o -g "${APP_GID}" ftpgroup; \
    usermod -o -u "${APP_UID}" -g "${APP_GID}" ftpuser; \
    mkdir -p /etc/pure-ftpd /var/www/html; \
    chown -R ftpuser:ftpgroup /var/www/html

COPY entrypoint /usr/local/bin/oneinstack-pureftpd-entrypoint
COPY manage-user /usr/local/bin/ftp-user

RUN chmod 0755 \
    /usr/local/bin/oneinstack-pureftpd-entrypoint \
    /usr/local/bin/ftp-user

EXPOSE 21 30000-30009

ENTRYPOINT ["/usr/local/bin/oneinstack-pureftpd-entrypoint"]
