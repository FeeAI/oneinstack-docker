ARG OPENRESTY_VERSION=1.31.1.1-2-alpine
FROM openresty/openresty:${OPENRESTY_VERSION}

LABEL org.opencontainers.image.title="OneinStack OpenResty"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d /etc/nginx/conf.d

RUN cp /etc/nginx/conf.d/default.conf /tmp/default.conf \
    && sed -i 's/fastcgi_pass php:9000;/fastcgi_pass 127.0.0.1:9000;/' /etc/nginx/conf.d/default.conf \
    && openresty -t \
    && mv /tmp/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443
