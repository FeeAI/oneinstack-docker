ARG OPENRESTY_VERSION=1.27.1.2-0-alpine
FROM openresty/openresty:${OPENRESTY_VERSION}

LABEL org.opencontainers.image.title="OneinStack OpenResty"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d /etc/nginx/conf.d

RUN openresty -t

EXPOSE 80 443
