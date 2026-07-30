ARG APACHE_VERSION=2.4
FROM httpd:${APACHE_VERSION}

LABEL org.opencontainers.image.title="OneinStack Apache"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

RUN set -eux; \
    sed -ri \
      -e 's!^#(LoadModule proxy_module modules/mod_proxy.so)!\1!' \
      -e 's!^#(LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so)!\1!' \
      -e 's!^#(LoadModule proxy_http_module modules/mod_proxy_http.so)!\1!' \
      -e 's!^#(LoadModule rewrite_module modules/mod_rewrite.so)!\1!' \
      -e 's!^#(LoadModule ssl_module modules/mod_ssl.so)!\1!' \
      -e 's!^#(LoadModule socache_shmcb_module modules/mod_socache_shmcb.so)!\1!' \
      /usr/local/apache2/conf/httpd.conf; \
    printf '\nServerName localhost\nListen 443\nIncludeOptional conf/oneinstack/*.conf\n' \
      >>/usr/local/apache2/conf/httpd.conf

COPY conf.d /usr/local/apache2/conf/oneinstack

RUN httpd -t

EXPOSE 80 443
