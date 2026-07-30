# OneinStack Docker

[English](README.md) | [中文](README.zh-CN.md) |
[能力矩阵](CAPABILITIES.md)

此目录提供 OneinStack 的容器化运行路径，不改变仓库根目录原有的宿主机源码
安装流程。已实现范围、明确缺口和当前运行时验收状态见
[CAPABILITIES.md](CAPABILITIES.md)。

## 支持范围

- Web：Nginx、Tengine、OpenResty、Caddy、Apache
- 数据库：MySQL、MariaDB、Percona、PostgreSQL、MongoDB
- 运行时：PHP 8.2-8.5、多 PHP、Composer、Node.js、Tomcat 9/10/11
- Java：Eclipse Temurin 8/11/17/21/25、用户自备 Oracle JDK 8u202
- 辅助服务：Redis、Memcached、phpMyAdmin、Adminer、TLS 优先的 Pure-FTPd
- 运维：虚拟主机、反向代理、TLS、备份恢复、健康检查、升级和清理

## 快速开始

```bash
cd docker
./oneinstack init
# 或指定其他宿主机绝对路径：
./oneinstack init --data-dir /srv/oneinstack
./oneinstack doctor
./oneinstack show-config
./oneinstack up
```

默认栈为 Nginx + PHP 8.4 + MySQL 8.4。未提供 `--data-dir` 时，初始化使用
管理脚本旁的 `docker/data`。初始化同时生成权限为 `0600` 的 `.env`、
`secrets/` 下权限为 `0600` 的随机密钥文件以及托管目录标记，不会覆盖已有
配置。生成的四个 `*_PASSWORD_FILE` 是明确的密钥来源配置项，服务密码值
不再以内联明文保存在 `.env`。

## 选择服务

`configure` 事务式更新 `.env`，全部组合校验通过后才会替换原配置：

```bash
./oneinstack configure --web openresty --db mariadb
./oneinstack configure --web caddy --db postgresql --enable adminer
./oneinstack configure --php 8.5 \
  --extensions imagick,redis,memcached,mongodb,pgsql,swoole
./oneinstack configure --enable cache,node,tomcat
./oneinstack configure --tomcat 10.1 --jdk 21 --node 22
./oneinstack configure --enable ftp --ftp-tls-domain ftp.example.com
./oneinstack configure --disable memcached,tomcat
```

修改选择后执行 `./oneinstack up`，Compose 会构建并重建需要的服务。

## 共享服务网络

容器间使用 Compose 服务名和共享 bridge 直连：

```text
公网 -> Web -> backend -> PHP / Node / Tomcat -> 数据库 / 缓存
                         \-> egress -> 外部 API
```

- Nginx、Tengine、OpenResty、Caddy、Apache 加入 `frontend + backend`。
- PHP、Node.js、Tomcat 加入 `backend + egress`。
- 数据库、Redis、Memcached 只加入内部 `backend`。
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

## Java 与 Oracle JDK 8u202

Java 默认使用 Temurin，支持矩阵如下：

| Tomcat | JDK |
| --- | --- |
| 9.0 | 8、11、17、21、25 |
| 10.1 | 11、17、21、25 |
| 11.0 | 17、21、25 |

Oracle JDK 8u202 仅作为要求固定厂商版本的 Linux AMD64 兼容路径。
OneinStack 不下载、不提交 Oracle 安装包。使用者需要通过有权限的 Oracle
账号下载、审阅 BCL，并将文件放在
`tomcat/oracle/jdk-8u202-linux-x64.tar.gz`，然后计算 SHA-256：

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

归档文件已被 Git 忽略，构建时会验证 SHA-256 和实际 Java 版本。Oracle
将 8u202 定义为缺少后续安全补丁的归档版本，不建议用于生产。发布包含
Oracle JDK 的公共镜像前，发布者必须自行确认满足 BCL；持续安全更新的
Temurin 8 仍是默认选择。

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
```

备份包含网站、站点配置、Tomcat webapps、FTP 虚拟用户状态和当前数据库。
MySQL、MariaDB、Percona、PostgreSQL 生成 `database-数据库类型.sql.gz`
压缩 SQL；MongoDB 生成 `database-mongodb.archive.gz` 压缩归档。数据库
恢复会拒绝 manifest 引擎与当前数据库不一致的备份。远端复制要求宿主机已
安装并配置 `rclone`。恢复会覆盖同名文件，因此要求 `--yes`。两种 purge
都保留 `backups/`。本地备份默认保留 180 天，可通过 `.env` 的
`BACKUP_RETENTION_DAYS` 调整。180 天是统一运营基线，不能替代特定国家、
地区或行业的保留期限要求。

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

只有以下命令才清理数据库、Redis、Caddy 状态和 FTP 凭据：

```bash
./oneinstack purge --data --yes
```

数据清理前会验证数据根目录托管标记。即使使用数据清理模式，也不删除网站、
证书、生成配置、日志和备份。

## 数据位置

默认根目录为 `docker/data`，也可在初始化时指定：

```bash
./oneinstack init --data-dir /data/oneinstack
```

对应目录如下：

- 网站、证书、ACME、日志、站点和备份：`www/`、`certs/`、`acme/`、
  `logs/`、`sites/`、`backups/`
- 数据库和 Redis 默认密钥文件：`secrets/`，文件权限为 `0600`
- Web 生成配置：`config/`
- 数据库：`mysql/`、`mariadb/`、`percona/`、`postgresql/`、`mongodb/`
- 其他状态：`redis/`、`caddy/`、`ftp/`、`tomcat/webapps/`

所有持久数据都使用明确的宿主机 bind mount，不再使用 Docker named
volume。`./oneinstack show-config` 会显示当前宿主机数据根目录。

`.env` 中四个 `*_PASSWORD_FILE` 配置项也可以指向默认 `secrets/` 之外的
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
