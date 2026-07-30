ARG APISIX_VERSION=3.17.0-debian
FROM apache/apisix:${APISIX_VERSION}

USER root
RUN rm -f /etc/apt/sources.list.d/apisix.list \
    && apt-get update \
    && apt-get install --yes --no-install-recommends curl libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*
COPY secrets-entrypoint /usr/local/bin/oneinstack-apisix-entrypoint
ENTRYPOINT ["/usr/local/bin/oneinstack-apisix-entrypoint"]
CMD ["docker-start"]
