# OneinStack Docker

[English](README.md) | [中文](README.zh-CN.md) |
[Capability matrix](CAPABILITIES.md) | [能力矩阵](CAPABILITIES.zh-CN.md)

本项目是 [OneinStack 源码安装项目](https://github.com/FeeAI/oneinstack)
对应的独立 Docker Compose 版本。已实现范围、明确缺口和当前运行时验收
状态见 [CAPABILITIES.zh-CN.md](CAPABILITIES.zh-CN.md)。

## 支持范围

- Web：Nginx、Tengine、OpenResty、Caddy、Apache、Nginx Proxy Manager
- 数据库：MySQL 8.4/9.7；MariaDB 10.11/11.4/11.8；Percona 8.4；
  PostgreSQL 15/16/17/18；MongoDB 7.0/8.0/8.3
- 运行时：PHP 8.2/8.3/8.4/8.5、多 PHP、Composer、Node.js 官方主版本标签、
  Tomcat 9.0/10.1/11.0
- Java：仍受维护的 Eclipse Temurin 8/11/17/21/25 LTS
- 辅助服务：Apache APISIX、Redis、Memcached、phpMyAdmin、Adminer、TLS 优先的
  Pure-FTPd；镜像版本选项也接受上游标签
- 运维：虚拟主机、反向代理、TLS、备份恢复、健康检查、升级和清理

## 快速开始

```bash
git clone https://github.com/FeeAI/oneinstack-docker.git
cd oneinstack-docker
./oneinstack init
# 或指定其他宿主机绝对路径：
./oneinstack init --data-dir /srv/oneinstack
./oneinstack doctor
./oneinstack show-config
./oneinstack up
```

默认栈为 Nginx + PHP 8.5 + MySQL 9.7 LTS。未提供 `--data-dir` 时，初始化使用
管理脚本旁的 `data`。初始化同时生成权限为 `0600` 的 `.env`、
`secrets/` 下权限为 `0600` 的随机密钥文件以及托管目录标记，不会覆盖已有
配置。生成的 `*_FILE` 是明确的服务密钥来源配置项，密钥值
不再以内联明文保存在 `.env`。

## 选择服务

`configure` 事务式更新 `.env`，全部组合校验通过后才会替换原配置：

`./oneinstack configure -h` 的完整参数说明如下：

<!-- oneinstack-configure-help:start -->
```text
Configure the OneinStack Docker deployment

Usage:
  ./oneinstack configure [options]

Options:
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
  upstream rolling tag while preserving required FPM/Alpine/slim variants.

Examples:
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
```

`configure` 暴露的每个版本参数都额外接受特殊值 `latest`，并解析为对应官方上游
容器镜像的滚动标签，包括 PHP、数据库、Redis、Memcached、Node.js、Tomcat、
phpMyAdmin、Adminer 和 APISIX。必要的镜像变体会保留，例如 PHP 使用
`php:fpm-bookworm`、Redis 使用 `redis:alpine`、Node.js 使用
`node:bookworm-slim`。Tomcat 与 JDK 是同一个上游镜像组合；
任一使用 `latest` 时都会选择完整的 `tomcat:latest`，因此两者显示版本都变为
`latest`。并行 PHP 仍必须指定 8.2-8.5，因为 Compose 服务名包含明确分支。

`latest` 是滚动标签，会跳过受维护系列白名单。固定默认值仍是面向生产环境的选择；
只有能够接受上游自动跨主版本更新时才应使用 `latest`。

`--db` 支持 `ENGINE[:VERSION]`。指定版本时覆盖 `.env` 中对应的镜像版本；
不指定版本时保留 `.env` 现有值：

```bash
./oneinstack configure --db mysql:8.4       # 选择较旧的受支持 LTS
./oneinstack configure --db mysql:9.7       # 选择当前 LTS
./oneinstack configure --db mariadb:11.8    # 写入 MARIADB_VERSION=11.8
./oneinstack configure --db mysql           # 保留当前 MYSQL_VERSION
```

`percona`、`postgresql`、`mongodb` 同样支持该格式；例如
`postgresql:17` 会写入 `POSTGRES_VERSION=17`。版本值只能使用 Docker tag
安全字符。
除显式滚动值 `latest` 外，管理器仅接受常规公开维护期至少还剩一年的版本系列：

- MySQL `8.4`、`9.7` LTS
- MariaDB `10.11`、`11.4`、`11.8`（默认 `11.8`）
- Percona Server `8.4`
- PostgreSQL `15`、`16`、`17`、`18`
- MongoDB `7.0`、`8.0`、`8.3`

剩余维护期校验会读取当前日期；某个系列越过一年门槛后，即使仍在上述名单中也会
被拒绝。付费延长支持或 EOL 后支持不计入维护期。具体依据各上游生命周期页面：
[MySQL](https://dev.mysql.com/doc/refman/8.4/en/mysql-releases.html)、
[MariaDB](https://mariadb.org/about/#maintenance-policy)、
[Percona](https://www.percona.com/release-lifecycle-overview/)、
[PostgreSQL](https://www.postgresql.org/support/versioning/) 和
[MongoDB](https://www.mongodb.com/legal/support-policy/lifecycles)。

Redis、Memcached、phpMyAdmin、Adminer 和 APISIX 通过各自的专用选项设置镜像
版本。指定其中任一选项时也会自动启用对应服务：

```bash
./oneinstack configure --redis 8.8 --memcached 1.6
./oneinstack configure --phpmyadmin 5-apache --adminer 5-standalone
./oneinstack configure --apisix 3.17.0-debian
```

修改选择后执行 `./oneinstack up`，Compose 会构建并重建需要的服务。

## 共享服务网络

容器间使用 Compose 服务名和共享 bridge 直连：

```text
公网 -> Web -> backend -> PHP / Node / Tomcat -> 数据库 / 缓存
                         \-> egress -> 外部 API
```

- Nginx、Tengine、OpenResty、Caddy、Apache、Nginx Proxy Manager、APISIX 加入
  `frontend + backend`。
- PHP、Node.js、Tomcat 加入 `backend + egress`。
- 数据库、Redis、Memcached 和 APISIX 的 etcd 只加入内部 `backend`。
- `php:9000`、`tomcat:8080`、`mysql:3306` 等内部连接不经过宿主机端口和
  NAT 回环。

这样内部服务之间只有一条明确的共享网络路径，同时运行时仍能通过独立
`egress` 访问外部 API；不会使用 host 网络，也不会发布数据库端口。

## 运行保护

完整执行 `up` 或 `update` 时，管理入口会先启动选定的数据库和缓存，等待
健康检查通过后再启动应用层；随后等待所有选中服务达到健康或运行状态才
返回。Web 服务还通过 Compose 等待主 PHP 健康。默认等待 180 秒，可用
`STARTUP_HEALTH_TIMEOUT` 调整。

每个服务均设置 CPU、内存、PID 上限和 Docker JSON 日志轮转。默认值按
Web、PHP、数据库、运行时、辅助服务分组，可在 `.env` 中调整对应的
`*_MEMORY_LIMIT`、`*_CPUS`、`*_PIDS_LIMIT`；单容器日志轮转由
`CONTAINER_LOG_MAX_SIZE` 和 `CONTAINER_LOG_MAX_FILES` 控制。

数据库和 Redis 密码通过 Compose secrets 从 `.env` 配置的
`*_PASSWORD_FILE` 路径挂载。旧 `.env` 中非占位的内联密码会在下一次配置
校验时迁移到密钥文件，并从 `.env` 清空。每个父目录应保持 `0700`、文件
保持 `0600`，应纳入受保护的灾难恢复流程，不进入普通内容备份。

密钥配置有统一入口，值不会出现在命令行参数中：

```bash
./oneinstack secret list
./oneinstack secret set database --file /secure/oneinstack/db-password
printf '%s\n' 'new-redis-password' | ./oneinstack secret set redis --stdin
./oneinstack secret set mongodb-root --generate
```

使用 `--path FILE` 可修改宿主机密钥文件路径。服务数据已经存在时，命令
默认拒绝直接替换凭据；应先在数据库内部完成账号密码轮换，再使用
`--after-rotation` 更新文件，并重建受影响容器以重新挂载新密钥。

## 多 PHP

只提供 [php.net 当前支持的分支](https://www.php.net/supported-versions.php)。
截至 2026 年 8 月为 PHP 8.2-8.5；8.2 和 8.3 仅接收安全修复，8.4 和
8.5 仍在主动支持期。停止支持的分支会被移除，不作为“兼容选项”保留。

主 PHP 由 `configure --php` 选择。额外 PHP-FPM 可以并行运行：

```bash
./oneinstack php-runtime add 8.2
./oneinstack php-runtime add 8.5
./oneinstack php-runtime list
./oneinstack php-runtime remove 8.2
```

站点可使用 `php`、`php82`、`php83`、`php84` 或 `php85`。

## PHP 扩展

扩展在镜像构建期安装，所有并行 PHP 默认使用同一扩展选择：

```bash
./oneinstack php-ext list
./oneinstack php-ext set imagick,redis,mongodb,pgsql,phalcon,yar
./oneinstack php-ext add swoole,xdebug
./oneinstack php-ext remove xdebug
./oneinstack build php
./oneinstack up php
./oneinstack php-ext verify
```

内建支持 Calendar、Fileinfo、IMAP、LDAP、OPcache、PostgreSQL，以及
APCu、Imagick、Memcache、Memcached、MongoDB、Phalcon、Redis、Swoole、
Xdebug、Yaf、Yar。`yar` 自动安装 Msgpack。

SQL Server 驱动会同时安装 `sqlsrv`、`pdo_sqlsrv` 和 Microsoft ODBC 18，
当前固定版本要求 PHP 8.3 或更新版本，并且必须显式接受 Microsoft EULA：

```bash
./oneinstack configure \
  --extensions imagick,redis,sqlsrv \
  --accept-microsoft-eula
```

额外 PECL 包必须固定包版本，并声明加载后的模块名：

```bash
./oneinstack configure --pecl-extra uuid@uuid-1.3.0
./oneinstack configure --pecl-extra none
```

不能再分发的授权加载器或私有模块可放入 `php/custom/extensions/`，对应
INI 放入 `php/custom/conf.d/`。二进制必须匹配 PHP 版本、NTS、CPU 架构和
libc；构建过程会拒绝产生 PHP startup error 的模块。

## Java 与 Tomcat

Java 默认使用开源 LTS 发行版 Temurin 25，但它不是唯一仍受维护的选择。
[Adoptium 路线图](https://adoptium.net/support/) 仍将 Temurin 8、11、17、21、25
列为可用 LTS。支持组合遵循 Tomcat 的 Java 最低版本要求：

| Tomcat | 受维护的 JDK 选择 |
| --- | --- |
| 9.0 | Temurin 8、11、17、21、25 |
| 10.1 | Temurin 11、17、21、25 |
| 11.0 | Temurin 17、21、25 |

需要仍受维护的 Java 8 时，可直接选择 Temurin 8。它使用上游 Tomcat Docker
Official Image：

```bash
./oneinstack configure --tomcat 9.0 --jdk 8
./oneinstack build tomcat
```

不提供缺少持续维护上游容器镜像来源的 JDK 发行版。Temurin 25 保持默认。

## 站点和反向代理

```bash
./oneinstack site add example.com --runtime php
./oneinstack site add legacy.example.com --runtime php82
./oneinstack site add api.example.com --runtime node
./oneinstack site add java.example.com --runtime tomcat
./oneinstack site add proxy.example.com \
  --runtime proxy --target upstream:8080
./oneinstack site add static.example.com --runtime static --tls off
./oneinstack site list
./oneinstack site delete example.com
```

站点元数据保存在数据根目录的 `sites/`，原生配置渲染到 `config/`。切换
Web 引擎后会重新渲染全部站点。删除站点默认保留网站文件；只有显式增加
`--purge` 才删除数据根目录中对应的 `www/` 子目录。

如果 Web 容器正在运行，站点变更后会自动校验并 reload；未运行时只生成配置。

## TLS

Caddy 对域名站点自动申请和续期证书。其他 Web 引擎支持 Certbot HTTP-01：

```bash
./oneinstack tls issue example.com admin@example.com
./oneinstack tls renew
./oneinstack tls self-signed internal.example.com
sudo ./oneinstack tls timer-install
./oneinstack tls timer-status
# 明确卸载：
sudo ./oneinstack tls timer-remove
```

证书保存在数据根目录的 `certs/`，ACME webroot 位于 `acme/`。DNS
challenge 插件尚未由统一入口配置。证书签发或续期后，管理入口会 reload
正在运行的 Web 服务，并重启正在运行的 FTP 服务，使其读取新证书。
在 systemd 宿主机上，`timer-install` 会安装带随机延迟、持久化的每日两次
续期任务。任务调用本管理入口的 `tls renew`，不会向容器挂载 Docker Socket。

[Nginx Proxy Manager](https://nginxproxymanager.com/guide/) 是独立的
UI 管理型 Web 引擎：

```bash
./oneinstack configure --web npm
./oneinstack up
# 打开 http://127.0.0.1:81
```

它使用官方 SQLite 最小部署，将 `/data` 和 `/etc/letsencrypt` 持久化到
`npm/`。代理主机和证书由 NPM 管理界面维护；`site` 和基于 Certbot 的
`tls issue` 不会伪装能修改 NPM 内部数据库。镜像版本与仅监听回环地址的
管理端口可通过 `NPM_VERSION`、`NPM_ADMIN_BIND`、`NPM_ADMIN_PORT` 调整。

[Apache APISIX](https://apisix.apache.org/docs/docker/manual/) 是可与任意 Web
引擎并行启用的 API Gateway：

```bash
./oneinstack configure --enable apisix
./oneinstack up
# Dashboard：http://127.0.0.1:9180/ui/
```

Gateway HTTP/HTTPS 默认监听 `9080`/`9443`。Dashboard 与 Admin API 共用
`9180`，默认仅绑定回环地址，并要求使用 `APISIX_ADMIN_KEY_FILE` 指向的
Admin API 密钥。APISIX 采用 traditional 模式和仅在后端网络可见的 etcd，
通过 Admin API 或内置 Dashboard 建立的路由持久化到 `apisix/etcd`。它是
API Gateway，不替代 PHP 虚拟主机；上游可指向共享后端网络中的
`nginx:80`、`node:3000`、`tomcat:8080` 等现有服务。

## 数据库与工具

```bash
./oneinstack db
./oneinstack configure --enable phpmyadmin
./oneinstack configure --enable adminer
```

phpMyAdmin 仅允许 MySQL、MariaDB、Percona；Adminer 可用于其他关系数据库。
管理工具默认只监听回环地址。数据库端口不发布到宿主机，应用使用 Compose
服务名连接。

## 备份恢复

```bash
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
```

备份包含网站、站点配置、Tomcat webapps、NPM 状态、FTP 虚拟用户状态和当前数据库。
MySQL、MariaDB、Percona、PostgreSQL 生成 `database-数据库类型.sql.gz`
压缩 SQL；MongoDB 生成 `database-mongodb.archive.gz` 压缩归档。数据库
恢复会拒绝 manifest 引擎与当前数据库不一致的备份。远端复制要求宿主机已
安装并配置 `rclone`。恢复会覆盖同名文件，因此要求 `--yes`。两种 purge
都保留 `backups/`。本地备份默认保留 180 天，可通过 `.env` 的
`BACKUP_RETENTION_DAYS` 调整。180 天是统一运营基线，不能替代特定国家、
地区或行业的保留期限要求。

启用 APISIX 后，创建备份要求其 etcd 服务健康，并通过 `etcdctl` 生成一致性
快照。`restore-apisix` 会替换全部 Gateway 路由和状态、重启 APISIX，因此必须
显式提供 `--yes`。

创建备份时会先取得互斥锁，在隐藏的临时目录生成数据、完成标记和
`SHA256SUMS`，全部成功后通过一次原子重命名提交正式时间戳目录；远端复制
只会在提交后开始。恢复会先核对所选文件的 SHA-256。

可使用宿主机已有的 `age` 对数据载荷进行静态加密：

```bash
# 创建备份前写入 .env：
BACKUP_AGE_RECIPIENT=age1...
# 仅恢复主机需要：
BACKUP_AGE_IDENTITY_FILE=/secure/path/age-key.txt
./oneinstack backup create
./oneinstack backup restore-web \
  data/backups/TIMESTAMP/webroot.tar.gz.age --yes
```

完成清单和校验文件保持明文，便于识别和验证备份集；网站、配置和数据库
载荷会被加密。

## Pure-FTPd

```bash
./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
./oneinstack site add ftp.example.com --runtime static
./oneinstack up nginx
./oneinstack tls issue ftp.example.com admin@example.com
./oneinstack up ftp
./oneinstack ftp-user add deploy example.com
./oneinstack ftp-user passwd deploy
./oneinstack ftp-user list
./oneinstack ftp-user delete deploy
```

FTP 使用虚拟用户，不创建宿主机账号。默认 `required` 模式强制控制和数据
通道全部使用 TLS。只有明确执行 `--ftp-tls-mode off` 才允许明文兼容模式，
该模式会暴露账号、密码和文件内容，不建议使用。公网部署还必须在 `.env`
设置 `FTP_PUBLIC_HOST`，并仅开放配置的被动端口范围。

完整 `up` 发现配置的 FTPS 证书不存在时，会自动生成有效期一年的 RSA
自签名证书。终端只显示证书路径、私钥路径和 SHA-256 指纹，不会输出私钥
内容。替换为受信任 CA 签发的证书前，FTP 客户端会提示该自签名证书不受信任。

## 日常管理

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

`down` 保留宿主机数据。普通 purge 仅删除容器、网络和可重新构建的本地
镜像，保留全部宿主机数据：

```bash
./oneinstack purge --yes
```

只有以下命令才清理数据库、Redis、Caddy、NPM、APISIX 状态和 FTP 凭据：

```bash
./oneinstack purge --data --yes
```

数据清理前会验证数据根目录托管标记。即使使用数据清理模式，也不删除网站、
证书、生成配置、日志和备份。

## 数据位置

默认根目录为 `data`，也可在初始化时指定：

```bash
./oneinstack init --data-dir /data/oneinstack
```

对应目录如下：

- 网站、证书、ACME、日志、站点和备份：`www/`、`certs/`、`acme/`、
  `logs/`、`sites/`、`backups/`
- 服务默认密钥文件：`secrets/`，文件权限为 `0600`
- Web 生成配置：`config/`
- 数据库：`mysql/`、`mariadb/`、`percona/`、`postgresql/`、`mongodb/`
- 其他状态：`redis/`、`caddy/`、`npm/`、`apisix/etcd/`、`ftp/`、`tomcat/webapps/`

所有持久数据都使用明确的宿主机 bind mount，不再使用 Docker named
volume。`./oneinstack show-config` 会显示当前宿主机数据根目录。

`.env` 中的服务密钥 `*_FILE` 配置项也可以指向默认 `secrets/` 之外的
受保护路径，例如由宿主机密钥管理系统提供的文件。对于已有的外部托管文件，
工具不会修改文件及其父目录的所有者或权限；部署方需确保配置的 `APP_UID`
具备读取权限。

数据库初始化文件分别放在 `mysql/initdb/`、`mariadb/initdb/`、
`percona/initdb/`、`postgresql/initdb/`、`mongodb/initdb/`。它们只在
对应空数据目录第一次初始化时执行。

## 生产环境边界

- 固定镜像补丁版本或摘要，先在测试环境执行数据库主版本升级。
- `.env` 不应进入镜像或仓库；高安全环境应迁移到平台 secret 机制。
- 宿主机防火墙、SSH、Fail2ban 和计划任务仍由部署平台负责。
- 当前工作站没有 Docker，仓库内已完成静态与脚本生命周期验证，但仍需在
  有 Docker 的 Linux 测试机执行真实构建、健康检查、TLS 和恢复演练。
