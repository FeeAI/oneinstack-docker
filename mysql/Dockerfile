ARG MYSQL_VERSION=8.4
FROM mysql:${MYSQL_VERSION}

LABEL org.opencontainers.image.title="OneinStack MySQL"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY conf.d/oneinstack.cnf /etc/mysql/conf.d/oneinstack.cnf
