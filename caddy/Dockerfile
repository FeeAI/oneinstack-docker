ARG CADDY_VERSION=2.11.4
FROM caddy:${CADDY_VERSION}-alpine

LABEL org.opencontainers.image.title="OneinStack Caddy"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY Caddyfile /etc/caddy/Caddyfile
COPY sites /etc/caddy/sites

RUN caddy validate --config /etc/caddy/Caddyfile

EXPOSE 80 443
