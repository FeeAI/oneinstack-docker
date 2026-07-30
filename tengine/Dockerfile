FROM alpine:3.22 AS builder

ARG TENGINE_VERSION=3.1.0
ARG TENGINE_SHA256=64ed7155c0c904ce0fe7199c21b8eb6c2abfc267278fa8af832c0cb781e864dc

RUN set -eux; \
    apk add --no-cache \
      build-base \
      linux-headers \
      openssl-dev \
      pcre2-dev \
      wget \
      zlib-dev; \
    wget -O /tmp/tengine.tar.gz \
      "https://github.com/alibaba/tengine/archive/refs/tags/${TENGINE_VERSION}.tar.gz"; \
    echo "${TENGINE_SHA256}  /tmp/tengine.tar.gz" | sha256sum -c -; \
    mkdir /tmp/tengine; \
    tar -xzf /tmp/tengine.tar.gz -C /tmp/tengine --strip-components=1; \
    cd /tmp/tengine; \
    ./configure \
      --prefix=/usr/local/tengine \
      --with-http_gzip_static_module \
      --with-http_realip_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      --with-http_v2_module \
      --with-pcre-jit; \
    make -j"$(getconf _NPROCESSORS_ONLN)"; \
    make install

FROM alpine:3.22

LABEL org.opencontainers.image.title="OneinStack Tengine"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

RUN apk add --no-cache ca-certificates openssl pcre2 wget zlib

COPY --from=builder /usr/local/tengine /usr/local/tengine
COPY nginx.conf /usr/local/tengine/conf/nginx.conf
COPY conf.d /usr/local/tengine/conf/conf.d

RUN cp /usr/local/tengine/conf/conf.d/default.conf /tmp/default.conf \
    && sed -i 's/fastcgi_pass php:9000;/fastcgi_pass 127.0.0.1:9000;/' /usr/local/tengine/conf/conf.d/default.conf \
    && /usr/local/tengine/sbin/nginx -t \
    && mv /tmp/default.conf /usr/local/tengine/conf/conf.d/default.conf

EXPOSE 80 443

CMD ["/usr/local/tengine/sbin/nginx", "-g", "daemon off;"]
