# Container capability matrix

[English](CAPABILITIES.md) | [中文](CAPABILITIES.zh-CN.md)

This matrix measures functional parity for responsibilities that belong inside
a container deployment. Host SSH configuration, host firewall policy, distro
package initialization and reboot control are intentionally excluded: running
those operations from an application container would not be equivalent or safe.

The score measures outcomes, not whether the original source-compilation steps
are repeated inside an image.

| Area | Implementation status | Notes |
| --- | --- | --- |
| Stack selection and installation | Implemented | Transactional selection, local builds, health checks and Compose profiles |
| Web servers, virtual hosts and proxies | Implemented | Nginx, Tengine, OpenResty, Caddy, Apache, UI-managed Nginx Proxy Manager and APISIX API Gateway; PHP/static/Node/Tomcat/custom proxy sites |
| Database families and administration | Implemented | MySQL 8.4/9.7 LTS; MariaDB 10.11/11.4/11.8; Percona 8.4; PostgreSQL 15-18; MongoDB 7.0/8.0/8.3; phpMyAdmin and Adminer |
| PHP, multi-PHP, extensions and Composer | Implemented with gaps | Currently supported PHP 8.2-8.5 branches, parallel FPM, Composer, selectable extensions, pinned extra PECL and private binary hooks |
| Java/Tomcat and Node.js | Implemented | Tomcat 9/10/11 on Docker Official Image variants for maintained Temurin 8/11/17/21/25 LTS lines, plus Node.js |
| Redis, Memcached and Pure-FTPd | Implemented | Persistent Redis, isolated Memcached and FTPS virtual users |
| TLS certificate lifecycle | Implemented with external acceptance | Caddy automatic HTTPS, Certbot HTTP-01, renewal, self-signed certificates, FTPS reload and host systemd timer |
| Backup and restore | Implemented | Web, configuration, Tomcat, NPM, APISIX etcd snapshots, FTP and all database families; atomic checksummed sets, optional age encryption and rclone copies |
| Upgrade, uninstall and daily management | Implemented | Build/update, health waits, safe down/purge and separately confirmed marker-guarded data purge |
| Security and diagnostics | Implemented with external acceptance | Shared internal backend, isolated runtime egress, file secrets, resource/PID ceilings, log rotation, TLS-first FTP and health checks |

## Deliberate gaps

- End-of-life PHP, Tomcat and database releases are not presented as maintained
  choices. PHP follows php.net's supported branches. Database tracks need at
  least one year of regular public maintenance remaining; paid extended or
  post-EOL support does not qualify. The explicit rolling `latest` value tracks
  the official upstream container tag and is not a curated lifecycle claim.
  Open-source JDK choices follow Temurin LTS availability.
- Proprietary PHP loaders are not redistributed. ABI-matched vendor modules can
  be supplied through `php/custom`; their licensing remains the deployer's
  responsibility. Gmagick is not built in because its latest PECL release is
  still a release candidate.
- JDK distributions without a maintained upstream container image are not
  offered. Maintained Temurin LTS lines remain available, with Temurin 25 as
  the default JDK.
- Certbot HTTP-01 and Caddy automatic HTTPS are implemented. Provider-specific
  DNS challenge plugins are not configured by the manager.
- Backups can be copied to any configured rclone remote, but there is no
  interactive wizard for each cloud vendor or backup-specific host timer.
  Certificate renewal has an explicit systemd timer.
- Fail2ban, SSH port changes, firewall rules and reboot are host/platform
  responsibilities. Container health checks and network isolation replace only
  the parts that have a valid container equivalent.

Raw command-line option parity with the historical installer is intentionally
not used as a release-readiness score. Release readiness depends on the
acceptance evidence below.

## Validation status

Shell syntax, ShellCheck, Compose rendering, build contexts, configuration
transactions, site rendering, NPM and APISIX startup, secret generation, explicit host data-root
initialization, backup archive restore and local lifecycle behavior have been
checked. `tests/runtime.sh` defines the Docker Linux default-stack acceptance
and `.github/workflows/ci.yml` runs it in CI. Until that workflow passes,
image builds and service startup remain unaccepted. Database restore,
encrypted age restore, systemd timer activation, FTPS transfer, other optional
stack families and public ACME issuance still require scoped Docker-enabled
Linux acceptance.
