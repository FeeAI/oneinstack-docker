# OneinStack Docker

[English](README.md) | [中文](README.zh-CN.md) |
[Capability matrix](CAPABILITIES.md)

This directory provides a service-oriented container deployment without
changing the host source installer in the repository root. See
[CAPABILITIES.md](CAPABILITIES.md) for implemented areas, deliberate gaps and
the current runtime acceptance status.

## Supported stack

- Web: Nginx, Tengine, OpenResty, Caddy and Apache
- Databases: MySQL, MariaDB, Percona, PostgreSQL and MongoDB
- Runtimes: PHP 8.2-8.5, parallel PHP-FPM, Composer, Node.js and Tomcat 9-11
- Java: Eclipse Temurin 8/11/17/21/25 and user-supplied Oracle JDK 8u202
- Services: Redis, Memcached, phpMyAdmin, Adminer and TLS-first Pure-FTPd
- Operations: sites, proxies, TLS, backup/restore, health checks and upgrades

## Quick start

```bash
cd docker
./oneinstack init
# Or choose another absolute host path:
./oneinstack init --data-dir /srv/oneinstack
./oneinstack doctor
./oneinstack show-config
./oneinstack up
```

The default is Nginx + PHP 8.4 + MySQL 8.4. `init` uses `docker/data` beside the
manager script unless `--data-dir` is supplied. Initialization creates a mode
`0600` `.env`, mode `0600` random secret files under the selected data root, and
a managed-data marker; it never overwrites an existing environment file. The
generated `*_PASSWORD_FILE` entries in `.env` are the explicit configuration
for the four secret sources; service password values are not stored inline in
`.env`.

## Select the stack

```bash
./oneinstack configure --web openresty --db mysql:8.0
./oneinstack configure --db mariadb
./oneinstack configure --web caddy --db postgresql --enable adminer
./oneinstack configure --php 8.5 \
  --extensions imagick,redis,memcached,mongodb,pgsql,swoole
./oneinstack configure --enable cache,node,tomcat
./oneinstack configure --tomcat 10.1 --jdk 21 --node 22
./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
./oneinstack configure --disable memcached,tomcat
./oneinstack up
```

Configuration updates are transactional. Invalid combinations leave `.env`
unchanged.

`--db` accepts `ENGINE[:VERSION]`. A version suffix overrides the matching
image version in `.env`; omitting it preserves the existing `.env` value:

```bash
./oneinstack configure --db mysql:8.0       # sets MYSQL_VERSION=8.0
./oneinstack configure --db mariadb:11.8    # sets MARIADB_VERSION=11.8
./oneinstack configure --db mysql           # keeps the current MYSQL_VERSION
```

The same form applies to `percona`, `postgresql` and `mongodb`; for example,
`postgresql:17` sets `POSTGRES_VERSION=17` (the PostgreSQL builder adds its
Alpine variant). Version values must use Docker-tag-safe characters.

## Shared service networks

Container-to-container traffic uses service DNS names on a shared bridge:

```text
Internet -> Web -> backend -> PHP / Node / Tomcat -> database / cache
                         \-> runtime egress -> external APIs
```

- Nginx, Tengine, OpenResty, Caddy and Apache join `frontend` and `backend`.
- PHP, Node.js and Tomcat join `backend` and the outbound-only `egress` bridge.
- Databases, Redis and Memcached join only the internal `backend` bridge.
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
The defaults are grouped by web, PHP, database, runtime and auxiliary service;
adjust the corresponding `*_MEMORY_LIMIT`, `*_CPUS` and `*_PIDS_LIMIT`
variables in `.env`. `CONTAINER_LOG_MAX_SIZE` and
`CONTAINER_LOG_MAX_FILES` control per-container log rotation.

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

## Java and Oracle JDK 8u202

Temurin is the default Java distribution. The supported combinations are:

| Tomcat | JDK |
| --- | --- |
| 9.0 | 8, 11, 17, 21 or 25 |
| 10.1 | 11, 17, 21 or 25 |
| 11.0 | 17, 21 or 25 |

Oracle JDK 8u202 is an explicit Linux AMD64 compatibility path for applications
that require that exact vendor build. OneinStack never downloads or commits the
Oracle archive. Download it with an authorized Oracle account, review the BCL,
and place it at `tomcat/oracle/jdk-8u202-linux-x64.tar.gz`. Then calculate its
SHA-256 and configure:

```bash
./oneinstack configure \
  --tomcat 9.0 \
  --jdk 8 \
  --jdk-vendor oracle \
  --oracle-jdk8-sha256 SHA256 \
  --accept-oracle-bcl
./oneinstack doctor
./oneinstack build tomcat
```

The archive is ignored by Git and the build verifies its checksum and Java
version. Oracle describes 8u202 as an unpatched archive release and does not
recommend it for production. Public image redistribution must independently
satisfy the Oracle BCL; the default Temurin 8 path remains the maintained
choice.

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
Configuration, Tomcat webapps and FTP virtual-user state are separate,
independently restorable archives. Database restore rejects a backup whose
manifest engine does not match the currently selected database. Backups remain
under `backups/` after both purge modes. Local backup retention defaults to 180
days and is controlled by `BACKUP_RETENTION_DAYS` in `.env`. This is an
operational baseline, not a substitute for jurisdiction- or industry-specific
retention requirements.

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

Only the following explicit command clears database, Redis, Caddy and FTP data:

```bash
./oneinstack purge --data --yes
```

The data-root marker is checked first. Website files, certificates,
configuration, logs and backups are preserved even in data-purge mode.

## Host data layout

The default root is `docker/data`. A custom root selected by `init --data-dir`
has the same layout:

- `www/`, `certs/`, `acme/`, `logs/`, `sites/` and `backups/`
- `secrets/` for the default mode `0600` database and Redis secret files
- `config/` for generated web-server configuration
- `mysql/`, `mariadb/`, `percona/`, `postgresql/` and `mongodb/`
- `redis/`, `caddy/`, `ftp/` and `tomcat/webapps/`

All persistent service state uses explicit host bind mounts. Docker-managed
named volumes are not used, so the complete deployment data location is visible
from `./oneinstack show-config`.

The four `*_PASSWORD_FILE` entries in `.env` may point to protected paths
outside this default `secrets/` directory when a host secret manager provides
the files. Existing externally managed files and their parent directories are
not re-owned or re-permissioned; they must be readable by the configured
`APP_UID`.

Run `./oneinstack help` for the full command list. Host firewall, SSH, Fail2ban
and reboot remain deployment-platform responsibilities. Certificate scheduling
is available through the explicit systemd timer commands above; other recurring
jobs remain host responsibilities.
