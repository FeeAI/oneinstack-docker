# OneinStack Docker

[English](README.md) | [中文](README.zh-CN.md) |
[Capability matrix](CAPABILITIES.md) | [能力矩阵](CAPABILITIES.zh-CN.md)

This is the standalone Docker Compose companion to the
[OneinStack source installer](https://github.com/FeeAI/oneinstack). See
[CAPABILITIES.md](CAPABILITIES.md) for implemented areas, deliberate gaps and
the current runtime acceptance status.

## Supported stack

- Web: Nginx, Tengine, OpenResty, Caddy, Apache and Nginx Proxy Manager
- Databases: MySQL 8.4/9.7; MariaDB 10.11/11.4/11.8; Percona 8.4;
  PostgreSQL 15/16/17/18; MongoDB 7.0/8.0/8.3
- Runtimes: PHP 8.2/8.3/8.4/8.5, parallel PHP-FPM, Composer, Node.js
  official major tags and Tomcat 9.0/10.1/11.0
- Java: maintained Eclipse Temurin 8/11/17/21/25 LTS lines
- Services: Apache APISIX, Redis, Memcached, phpMyAdmin, Adminer and TLS-first
  Pure-FTPd; image-version options also accept upstream tags
- Operations: sites, proxies, TLS, backup/restore, health checks and upgrades

## Image base policy

Official Alpine images are preferred when they preserve the service contract
and maintained architecture coverage. The pinned defaults use Alpine for
Nginx 1.30.4, Tengine, OpenResty 1.31.1.1-2, Caddy 2.11.4, Apache 2.4.68,
PHP-FPM, PostgreSQL, Redis, Memcached, Node.js, Adminer, Certbot and Pure-FTPd.
The locally built Tengine and Pure-FTPd images use Alpine 3.24, supported until
June 2028.

An Alpine base is not substituted when the official image does not publish an
equivalent maintained tag or the service contract would change. MySQL,
MariaDB, Percona Server, MongoDB, Tomcat, Nginx Proxy Manager and APISIX retain
their official non-Alpine bases. phpMyAdmin retains its self-contained Apache
image because its Alpine tag is FPM-only. PHP switches to Bookworm
automatically when `sqlsrv` is selected because Microsoft's ODBC package is
not published for musl-based Alpine.

## Quick start

```bash
git clone https://github.com/FeeAI/oneinstack-docker.git
cd oneinstack-docker
./oneinstack init
# Or choose another absolute host path:
./oneinstack init --data-dir /srv/oneinstack
./oneinstack doctor
./oneinstack show-config
./oneinstack up
```

The default is Nginx + PHP 8.5 + MySQL 9.7 LTS. `init` uses `data` beside the
manager script unless `--data-dir` is supplied. Initialization creates a mode
`0600` `.env`, mode `0600` random secret files under the selected data root, and
a managed-data marker; it never overwrites an existing environment file. The
generated secret-file entries in `.env` are the explicit configuration for
service credentials; secret values are not stored inline in
`.env`.

## Select the stack

The complete `./oneinstack configure -h` reference is reproduced below:

<!-- oneinstack-configure-help:start -->
```text
Configure the OneinStack Docker deployment

Usage:
  ./oneinstack configure [options]

Options:
  --resource-profile PROFILE  small, balanced, large or custom
  --web ENGINE                 nginx, tengine, openresty, caddy, apache, npm or none
  --db ENGINE[:VERSION]        mysql, mariadb, percona, postgresql, mongodb or none
  --php VERSION                Primary PHP version: 8.2, 8.3, 8.4, 8.5 or latest
  --extensions LIST            Comma-separated maintained PHP extensions or none
  --pecl-extra LIST            MODULE@PACKAGE-VERSION entries or none
  --accept-microsoft-eula      Accept the EULA required by sqlsrv
  --enable LIST                Enable optional features
  --disable LIST               Disable optional features
  --redis VERSION              Enable Redis at an image version
  --memcached VERSION          Enable Memcached at an image version
  --node VERSION               Enable a Node.js major version or latest
  --tomcat VERSION             Enable Tomcat 9.0, 10.1, 11.0 or latest
  --jdk VERSION                Select Temurin LTS 8, 11, 17, 21, 25 or latest
  --phpmyadmin VERSION         Enable phpMyAdmin at an image version
  --adminer VERSION            Enable Adminer at an image version
  --apisix VERSION             Enable Apache APISIX at an image version
  --ftp-tls-mode MODE          required, optional or off
  --ftp-tls-domain DOMAIN      Certificate domain used by the FTP service
  -h, --help                   Show this help

Optional features:
  redis, memcached, cache, node, tomcat, phpmyadmin, adminer, apisix, ftp

Database versions:
  A VERSION suffix overrides the matching value in .env. Without a suffix,
  the existing version is preserved. Maintained tracks with at least one year
  remaining: MySQL 8.4/9.7; MariaDB 10.11/11.4/11.8; Percona 8.4;
  PostgreSQL 15/16/17/18; MongoDB 7.0/8.0/8.3.

Special version:
  Every configure version option accepts latest. It tracks the official
  upstream rolling tag while preserving required image variants.

Examples:
  ./oneinstack configure --resource-profile small
  ./oneinstack configure --web openresty --db mysql:9.7
  ./oneinstack configure --php 8.5 --extensions imagick,redis,mongodb,swoole
  ./oneinstack configure --redis 8.8 --memcached 1.6
  ./oneinstack configure --node 24 --tomcat 11.0 --jdk 25
  ./oneinstack configure --phpmyadmin 5-apache --adminer 5-standalone
  ./oneinstack configure --apisix 3.17.0-debian
  ./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
```
<!-- oneinstack-configure-help:end -->

```bash
./oneinstack configure --web openresty --db mysql:9.7
./oneinstack configure --web npm
./oneinstack configure --db mariadb
./oneinstack configure --web caddy --db postgresql --enable adminer
./oneinstack configure --php 8.5 \
  --extensions imagick,redis,memcached,mongodb,pgsql,swoole
./oneinstack configure --redis 8.8 --memcached 1.6
./oneinstack configure --phpmyadmin 5-apache --adminer 5-standalone
./oneinstack configure --apisix 3.17.0-debian
./oneinstack configure --enable node,tomcat
./oneinstack configure --tomcat 10.1 --jdk 25 --node 24
./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
./oneinstack configure --disable memcached,tomcat
./oneinstack up
```

Configuration updates are transactional. Invalid combinations leave `.env`
unchanged.

Every version argument exposed by `configure` also accepts the special value
`latest`. It resolves to the corresponding official upstream rolling tag,
including PHP, databases, Redis, Memcached, Node.js, Tomcat, phpMyAdmin,
Adminer and APISIX. Required image flavors are preserved: for example PHP uses
`php:fpm-alpine`, Redis uses `redis:alpine`, and Node.js uses
`node:alpine`. PHP uses `php:fpm-bookworm` only when `sqlsrv` is selected. For
Tomcat, either `--tomcat latest` or
`--jdk latest` selects the complete `tomcat:latest` image, so both displayed
versions become `latest`. Parallel PHP runtimes still require an explicit
8.2-8.5 branch because their Compose service names are versioned.

`latest` is intentionally rolling and bypasses curated lifecycle-series
selection. The pinned defaults remain the production-oriented choices; use
`latest` only when automatic upstream major-version movement is acceptable.

`--db` accepts `ENGINE[:VERSION]`. A version suffix overrides the matching
image version in `.env`; omitting it preserves the existing `.env` value:

```bash
./oneinstack configure --db mysql:8.4       # selects the older supported LTS
./oneinstack configure --db mysql:9.7       # selects the current LTS
./oneinstack configure --db mariadb:11.8    # sets MARIADB_VERSION=11.8
./oneinstack configure --db mysql           # keeps the current MYSQL_VERSION
```

The same form applies to `percona`, `postgresql` and `mongodb`; for example,
`postgresql:17` sets `POSTGRES_VERSION=17`. Version values must use
Docker-tag-safe characters.
The manager only accepts tracks with at least one year of regular public
maintenance remaining, unless the explicit rolling value `latest` is used:

- MySQL `8.4` and `9.7` LTS
- MariaDB `10.11`, `11.4` and `11.8` (default `11.8`)
- Percona Server `8.4`
- PostgreSQL `15`, `16`, `17` and `18`
- MongoDB `7.0`, `8.0` and `8.3`

The remaining-maintenance check is date-aware, so a listed track is rejected
after it crosses the one-year threshold. Paid extended or post-EOL support is
not counted. The policy follows the upstream lifecycle pages for
[MySQL](https://dev.mysql.com/doc/refman/8.4/en/mysql-releases.html),
[MariaDB](https://mariadb.org/about/#maintenance-policy),
[Percona](https://www.percona.com/release-lifecycle-overview/),
[PostgreSQL](https://www.postgresql.org/support/versioning/) and
[MongoDB](https://www.mongodb.com/legal/support-policy/lifecycles).

Redis, Memcached, phpMyAdmin, Adminer and APISIX accept image versions through their
dedicated options. Supplying one of these options also enables that service:

```bash
./oneinstack configure --redis 8.8 --memcached 1.6
./oneinstack configure --phpmyadmin 5-apache --adminer 5-standalone
./oneinstack configure --apisix 3.17.0-debian
```

## Shared service networks

Container-to-container traffic uses service DNS names on a shared bridge:

```text
Internet -> Web -> backend -> PHP / Node / Tomcat -> database / cache
                         \-> runtime egress -> external APIs
```

- Nginx, Tengine, OpenResty, Caddy, Apache, Nginx Proxy Manager and APISIX join
  `frontend` and `backend`.
- PHP, Node.js and Tomcat join `backend` and the outbound-only `egress` bridge.
- Databases, Redis, Memcached and APISIX's etcd join only the internal `backend` bridge.
- Internal service ports such as `php:9000`, `tomcat:8080` and `mysql:3306`
  are never routed through published host ports.

This gives each internal call one unambiguous shared-network path and avoids
host-port NAT. It does not use host networking or expose database ports.

## Runtime safeguards

`up` and full-stack `update` start the selected database and cache services
first, wait for their health checks, and only then start the application tier.
They then wait for every selected service to become healthy or running before
returning. Web services also use Compose's healthy-PHP dependency. The wait
defaults to 180 seconds and is configurable with `STARTUP_HEALTH_TIMEOUT`.

Every service has a CPU, memory and PID ceiling plus Docker JSON log rotation.
`RESOURCE_PROFILE=balanced` is the default. Change the complete resource set
transactionally with `./oneinstack configure --resource-profile small|balanced|large`.
The same synchronization occurs on the next manager command if
`RESOURCE_PROFILE` is edited directly. A preset owns its related container,
PHP-FPM, database, cache, Node.js and Tomcat limits, so select `custom` before
editing those individual values. Switching to `custom` preserves the currently
materialized values as a starting point.

| Profile | Web | PHP | Database | Runtime | Auxiliary |
| --- | ---: | ---: | ---: | ---: | ---: |
| `small` | 256 MB / 0.5 CPU | 512 MB / 1 CPU | 1 GB / 1 CPU | 512 MB / 1 CPU | 256 MB / 0.5 CPU |
| `balanced` | 512 MB / 1 CPU | 1 GB / 2 CPU | 2 GB / 2 CPU | 1 GB / 2 CPU | 512 MB / 1 CPU |
| `large` | 1 GB / 2 CPU | 2 GB / 4 CPU | 4 GB / 4 CPU | 2 GB / 4 CPU | 1 GB / 2 CPU |

`CONTAINER_LOG_MAX_SIZE` and `CONTAINER_LOG_MAX_FILES` remain independent and
control per-container log rotation.

Application limits are paired with those container ceilings. The 1 GB PHP
default uses a 256 MB per-request limit and at most three FPM workers, with
worker recycling, request timeouts, a slow log, realpath caching and OPcache.
The 2 GB MySQL-family default reserves 1 GB for the InnoDB buffer pool and
uses bounded connection and table caches. Redis reserves 128 MB of its 512 MB
container ceiling for allocator, persistence and client overhead by setting
`REDIS_MAXMEMORY=384mb`; the default `noeviction` policy preserves stored keys
and rejects writes when full. Change the related `PHP_*`, `PHP_FPM_*`,
`MYSQL_*` or `REDIS_*` values together with the container memory ceiling.
These are explicit container profiles, not host-memory autodetection.

Database and Redis passwords are mounted from the configured
`*_PASSWORD_FILE` paths through Compose secrets. Existing non-placeholder
inline passwords are migrated on the next validated manager command and then
cleared from `.env`. Keep each parent directory at mode `0700` and each file at
mode `0600`; include them in the deployment's protected disaster-recovery
procedure, not in normal content backups.

Secret configuration is explicit and value-safe:

```bash
./oneinstack secret list
./oneinstack secret set database --file /secure/oneinstack/db-password
printf '%s\n' 'new-redis-password' | ./oneinstack secret set redis --stdin
./oneinstack secret set mongodb-root --generate
```

Use `--path FILE` to change the configured host path. If service data already
exists, `secret set` refuses to replace the credential. Change the account
inside the running database first, then repeat with `--after-rotation` and
recreate the affected containers so the new secret mount is active.

## Multiple PHP runtimes

Only branches listed by [php.net as currently supported](https://www.php.net/supported-versions.php)
are offered. As of August 2026 these are PHP 8.2-8.5; 8.2 and 8.3 receive
security fixes only, while 8.4 and 8.5 remain in active support. End-of-life
branches are removed instead of being preserved as legacy choices.

```bash
./oneinstack php-runtime add 8.2
./oneinstack php-runtime add 8.5
./oneinstack php-runtime list
./oneinstack php-runtime remove 8.2
```

Sites can select `php`, `php82`, `php83`, `php84` or `php85`.

## PHP extensions

Extensions are installed at image build time. Parallel PHP runtimes use the
same selection by default:

```bash
./oneinstack php-ext list
./oneinstack php-ext set imagick,redis,mongodb,pgsql,phalcon,yar
./oneinstack php-ext add swoole,xdebug
./oneinstack php-ext remove xdebug
./oneinstack build php
./oneinstack up php
./oneinstack php-ext verify
```

The built-in catalog covers Calendar, Fileinfo, IMAP, LDAP, OPcache,
PostgreSQL, APCu, Imagick, Memcache, Memcached, MongoDB, Phalcon, Redis,
Swoole, Xdebug, Yaf and Yar. Yar installs Msgpack automatically.

`sqlsrv` installs both SQLSRV drivers and Microsoft ODBC 18, requires PHP 8.3
or newer, and requires explicit EULA acceptance:

```bash
./oneinstack configure \
  --extensions imagick,redis,sqlsrv \
  --accept-microsoft-eula
```

Pinned additional PECL packages use `MODULE@PACKAGE-VERSION`:

```bash
./oneinstack configure --pecl-extra uuid@uuid-1.3.0
./oneinstack configure --pecl-extra none
```

ABI-compatible licensed or private modules can be placed in
`php/custom/extensions/`, with their INI files in `php/custom/conf.d/`.
The build rejects PHP startup errors; vendor licensing remains the deployer's
responsibility.

## Java and Tomcat

Temurin 25 is the default open-source LTS distribution, but it is not the only
maintained choice. The [Adoptium roadmap](https://adoptium.net/support/) still
lists Temurin 8, 11, 17, 21 and 25 as available LTS lines. The supported
combinations follow Tomcat's Java requirements:

| Tomcat | Maintained JDK choices |
| --- | --- |
| 9.0 | Temurin 8, 11, 17, 21 or 25 |
| 10.1 | Temurin 11, 17, 21 or 25 |
| 11.0 | Temurin 17, 21 or 25 |

For maintained Java 8, select Temurin 8 directly. It uses the upstream Tomcat
Docker Official Image:

```bash
./oneinstack configure --tomcat 9.0 --jdk 8
./oneinstack build tomcat
```

JDK distributions without a maintained upstream container image are not
offered. Temurin 25 remains the default.

## Sites, proxies and TLS

```bash
./oneinstack site add example.com --runtime php
./oneinstack site add api.example.com --runtime node
./oneinstack site add java.example.com --runtime tomcat
./oneinstack site add proxy.example.com --runtime proxy --target upstream:8080
./oneinstack site list

./oneinstack tls issue example.com admin@example.com
./oneinstack tls renew
./oneinstack tls self-signed internal.example.com
sudo ./oneinstack tls timer-install
./oneinstack tls timer-status
# Explicit removal:
sudo ./oneinstack tls timer-remove
```

Caddy manages HTTPS automatically. Other web engines use the Certbot HTTP-01
webroot flow. Site definitions are stored independently and rendered into the
selected web server's native format. Certificate creation and renewal reload
the running web service and restart a running FTP service so it reads the
updated certificate. On a systemd host, `timer-install` installs a persistent
twice-daily host timer with randomized delay. The timer invokes this manager's
`tls renew` command and does not mount the Docker socket into a container.

[Nginx Proxy Manager](https://nginxproxymanager.com/guide/) is a separate
UI-managed web engine:

```bash
./oneinstack configure --web npm
./oneinstack up
# Open http://127.0.0.1:81
```

It uses the official SQLite deployment and persists `/data` and
`/etc/letsencrypt` under `npm/`. Proxy hosts and certificates are managed in
the NPM admin UI; the `site` and Certbot-based `tls issue` commands do not
pretend to edit NPM's internal database. Its image version and loopback-bound
admin port are configurable with `NPM_VERSION`, `NPM_ADMIN_BIND` and
`NPM_ADMIN_PORT`.

[Apache APISIX](https://apisix.apache.org/docs/docker/manual/) is an optional
API gateway that can run beside any selected web engine:

```bash
./oneinstack configure --enable apisix
./oneinstack up
# Dashboard: http://127.0.0.1:9180/ui/
```

Gateway HTTP/HTTPS listen on `9080`/`9443` by default. The Dashboard and Admin
API share port `9180`, bind to loopback by default and require the Admin API key
stored in the configured `APISIX_ADMIN_KEY_FILE`. APISIX uses traditional mode
with a private etcd service so routes created through the Admin API and embedded
Dashboard persist under `apisix/etcd`. APISIX is an API gateway, not a PHP
virtual-host replacement; upstreams can target existing services such as
`nginx:80`, `node:3000` or `tomcat:8080` on the shared backend network.

## Databases, backup and FTP

```bash
./oneinstack db
./oneinstack backup create
./oneinstack backup create --remote myremote:oneinstack
./oneinstack backup restore-db \
  data/backups/TIMESTAMP/database-mysql.sql.gz --yes
./oneinstack backup restore-web \
  data/backups/TIMESTAMP/webroot.tar.gz --yes
./oneinstack backup restore-config \
  data/backups/TIMESTAMP/configuration.tar.gz --yes
./oneinstack backup restore-tomcat \
  data/backups/TIMESTAMP/tomcat-webapps.tar.gz --yes
./oneinstack backup restore-ftp \
  data/backups/TIMESTAMP/ftp-state.tar.gz --yes
./oneinstack backup restore-npm \
  data/backups/TIMESTAMP/npm-state.tar.gz --yes
./oneinstack backup restore-apisix \
  data/backups/TIMESTAMP/apisix-etcd.snapshot.db --yes

./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
./oneinstack site add ftp.example.com --runtime static
./oneinstack up nginx
./oneinstack tls issue ftp.example.com admin@example.com
./oneinstack up ftp
./oneinstack ftp-user add deploy example.com
./oneinstack ftp-user list
```

Remote backup copies use an already configured host `rclone`. Database and
cache ports are internal. phpMyAdmin and Adminer bind to loopback by default.
Pure-FTPd requires encrypted control and data channels by default. Legacy
plaintext can be enabled only explicitly with `--ftp-tls-mode off`; this exposes
credentials and file contents and is not recommended.

MySQL, MariaDB, Percona and PostgreSQL backups are compressed SQL dumps named
`database-ENGINE.sql.gz`. MongoDB uses `database-mongodb.archive.gz`.
Configuration, Tomcat webapps, NPM state and FTP virtual-user state are separate,
independently restorable archives. Database restore rejects a backup whose
manifest engine does not match the currently selected database. Backups remain
under `backups/` after both purge modes. Local backup retention defaults to 180
days and is controlled by `BACKUP_RETENTION_DAYS` in `.env`. This is an
operational baseline, not a substitute for jurisdiction- or industry-specific
retention requirements.

When APISIX is enabled, backup creation requires its etcd service to be healthy
and creates a consistent `etcdctl` snapshot. `restore-apisix` replaces all
gateway routes and state, restarts APISIX and therefore requires `--yes`.

If the configured FTPS certificate is missing during a full-stack `up`, the
manager creates a one-year self-signed RSA certificate automatically. It prints
the certificate path, private-key path and SHA-256 fingerprint, but never prints
the private-key content. Clients will report the self-signed certificate as
untrusted until it is replaced with a certificate from a trusted issuer.

Backup creation is serialized with a lock and writes into a hidden partial
directory. Payloads, the completion manifest and `SHA256SUMS` are committed to
the timestamp directory with one atomic rename; remote copy starts only after
that commit. Restore verifies the selected file against `SHA256SUMS` first.

Optional at-rest encryption uses an existing host `age` installation:

```bash
# Set in .env before backup creation:
BACKUP_AGE_RECIPIENT=age1...
# Required only on a restore host:
BACKUP_AGE_IDENTITY_FILE=/secure/path/age-key.txt
./oneinstack backup create
./oneinstack backup restore-web \
  data/backups/TIMESTAMP/webroot.tar.gz.age --yes
```

The manifest and checksum list remain plaintext so operators can identify and
validate backup sets; website, configuration and database payloads are
encrypted.

## Daily management

```bash
./oneinstack ps
./oneinstack logs nginx php
./oneinstack reload
./oneinstack shell php
./oneinstack php -m
./oneinstack composer install
./oneinstack node npm --version
./oneinstack update
./oneinstack down
```

`down` keeps all host data. `./oneinstack purge --yes` removes containers,
networks and locally rebuildable images while preserving every host data
directory.

Only the following explicit command clears database, Redis, Caddy, NPM, APISIX and FTP data:

```bash
./oneinstack purge --data --yes
```

The data-root marker is checked first. Website files, certificates,
configuration, logs and backups are preserved even in data-purge mode.

## Host data layout

The default root is `data`. A custom root selected by `init --data-dir`
has the same layout:

- `www/`, `certs/`, `acme/`, `logs/`, `sites/` and `backups/`
- `secrets/` for default mode `0600` service secret files
- `config/` for generated web-server configuration
- `mysql/`, `mariadb/`, `percona/`, `postgresql/` and `mongodb/`
- `redis/`, `caddy/`, `npm/`, `apisix/etcd/`, `ftp/` and `tomcat/webapps/`

All persistent service state uses explicit host bind mounts. Docker-managed
named volumes are not used, so the complete deployment data location is visible
from `./oneinstack show-config`.

The credential `*_FILE` entries in `.env` may point to protected paths
outside this default `secrets/` directory when a host secret manager provides
the files. Existing externally managed files and their parent directories are
not re-owned or re-permissioned; they must be readable by the configured
`APP_UID`.

Run `./oneinstack help` for the full command list. Host firewall, SSH, Fail2ban
and reboot remain deployment-platform responsibilities. Certificate scheduling
is available through the explicit systemd timer commands above; other recurring
jobs remain host responsibilities.
