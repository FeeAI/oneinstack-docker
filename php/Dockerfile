ARG PHP_VERSION=8.4
ARG PHP_VARIANT=fpm-bookworm
FROM php:${PHP_VERSION}-${PHP_VARIANT}

ARG PHP_EXTENSIONS=imagick,redis,memcached,mongodb,pgsql
ARG PHPREDIS_VERSION=6.3.0
ARG PHP_MEMCACHED_VERSION=3.4.0
ARG PHP_MONGODB_VERSION=2.3.3
ARG PHP_IMAGICK_VERSION=3.8.1
ARG PHP_SWOOLE_VERSION=6.2.2
ARG PHP_XDEBUG_VERSION=3.5.3
ARG PHP_IMAP_VERSION=1.0.3
ARG PHP_APCU_VERSION=5.1.28
ARG PHP_YAF_VERSION=3.3.7
ARG PHP_MEMCACHE_VERSION=8.2
ARG PHP_PHALCON_VERSION=5.17.0
ARG PHP_MSGPACK_VERSION=3.0.1
ARG PHP_YAR_VERSION=2.3.4
ARG PHP_SQLSRV_VERSION=5.13.1
ARG PHP_EXTRA_PECL_PACKAGES=
ARG MICROSOFT_ODBC_ACCEPT_EULA=N
ARG APP_UID=1000
ARG APP_GID=1000

LABEL org.opencontainers.image.title="OneinStack PHP-FPM"
LABEL org.opencontainers.image.source="https://github.com/FeeAI/oneinstack"

ENV TZ=Asia/Singapore

RUN set -eux; \
    apt-get update; \
    php_build_packages=' \
      default-mysql-client \
      git \
      libbrotli-dev \
      libcurl4-openssl-dev \
      libfcgi-bin \
      libfreetype6-dev \
      libicu-dev \
      libjpeg62-turbo-dev \
      libldap2-dev \
      libmagickwand-dev \
      libmemcached-dev \
      libpng-dev \
      libpq-dev \
      libsasl2-dev \
      libssl-dev \
      libzip-dev \
      unzip'; \
    case ",${PHP_EXTENSIONS}," in \
      *,sqlsrv,*) php_build_packages="${php_build_packages} curl gnupg unixodbc-dev" ;; \
    esac; \
    apt-get install -y --no-install-recommends ${php_build_packages}; \
    case ",${PHP_EXTENSIONS}," in \
      *,sqlsrv,*) \
        [ "${MICROSOFT_ODBC_ACCEPT_EULA}" = 'Y' ] || { \
          echo 'sqlsrv requires MICROSOFT_ODBC_ACCEPT_EULA=Y' >&2; \
          exit 1; \
        }; \
        curl -fsSLo /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc; \
        gpg --batch --yes --dearmor \
          --output /usr/share/keyrings/microsoft-prod.gpg /tmp/microsoft.asc; \
        printf '%s\n' \
          'deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main' \
          >/etc/apt/sources.list.d/microsoft-prod.list; \
        apt-get update; \
        ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18; \
        rm -f /tmp/microsoft.asc \
          /etc/apt/sources.list.d/microsoft-prod.list \
          /usr/share/keyrings/microsoft-prod.gpg; \
        ;; \
    esac; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
      bcmath \
      exif \
      gd \
      intl \
      mysqli \
      opcache \
      pcntl \
      pdo_mysql \
      zip

COPY install-extensions /usr/local/bin/oneinstack-install-php-extensions
COPY custom /opt/oneinstack/php-custom

RUN set -eux; \
    chmod 0755 /usr/local/bin/oneinstack-install-php-extensions; \
    PHP_EXTENSIONS="${PHP_EXTENSIONS}" \
    PHPREDIS_VERSION="${PHPREDIS_VERSION}" \
    PHP_MEMCACHED_VERSION="${PHP_MEMCACHED_VERSION}" \
    PHP_MONGODB_VERSION="${PHP_MONGODB_VERSION}" \
    PHP_IMAGICK_VERSION="${PHP_IMAGICK_VERSION}" \
    PHP_SWOOLE_VERSION="${PHP_SWOOLE_VERSION}" \
    PHP_XDEBUG_VERSION="${PHP_XDEBUG_VERSION}" \
    PHP_IMAP_VERSION="${PHP_IMAP_VERSION}" \
    PHP_APCU_VERSION="${PHP_APCU_VERSION}" \
    PHP_YAF_VERSION="${PHP_YAF_VERSION}" \
    PHP_MEMCACHE_VERSION="${PHP_MEMCACHE_VERSION}" \
    PHP_PHALCON_VERSION="${PHP_PHALCON_VERSION}" \
    PHP_MSGPACK_VERSION="${PHP_MSGPACK_VERSION}" \
    PHP_YAR_VERSION="${PHP_YAR_VERSION}" \
    PHP_SQLSRV_VERSION="${PHP_SQLSRV_VERSION}" \
    PHP_EXTRA_PECL_PACKAGES="${PHP_EXTRA_PECL_PACKAGES}" \
      /usr/local/bin/oneinstack-install-php-extensions; \
    if [ "$(id -g www-data)" != "${APP_GID}" ]; then groupmod -o -g "${APP_GID}" www-data; fi; \
    if [ "$(id -u www-data)" != "${APP_UID}" ]; then usermod -o -u "${APP_UID}" -g "${APP_GID}" www-data; fi; \
    rm -rf /tmp/pear /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY fpm-pool.conf /usr/local/etc/php-fpm.d/zz-oneinstack.conf
COPY fpm-healthcheck /usr/local/bin/fpm-healthcheck
COPY secrets-entrypoint /usr/local/bin/oneinstack-secrets-entrypoint
COPY php.ini /usr/local/etc/php/conf.d/oneinstack.ini

RUN chmod 0755 /usr/local/bin/fpm-healthcheck /usr/local/bin/oneinstack-secrets-entrypoint \
    && php-fpm --test

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["oneinstack-secrets-entrypoint"]
CMD ["php-fpm"]
