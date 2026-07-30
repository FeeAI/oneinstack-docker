# 容器能力矩阵

[English](CAPABILITIES.md) | [中文](CAPABILITIES.zh-CN.md)

本矩阵衡量属于容器化部署职责范围内的功能一致性。宿主机 SSH 配置、
宿主机防火墙策略、发行版软件包初始化和重启控制被有意排除：从应用容器内
执行这些操作既不等价，也不安全。

评估的是功能结果，而不是是否在镜像内重复了原有的源码编译步骤。

| 领域 | 实现状态 | 说明 |
| --- | --- | --- |
| 技术栈选择与安装 | 已实现 | 事务化选择、本地构建、健康检查和 Compose profiles |
| Web 服务器、虚拟主机与代理 | 已实现 | Nginx、Tengine、OpenResty、Caddy、Apache、UI 管理的 Nginx Proxy Manager 和 APISIX API Gateway；支持 PHP、静态、Node、Tomcat 和自定义代理站点 |
| 数据库类型与管理 | 已实现 | MySQL 8.4/9.7 LTS、MariaDB、Percona、PostgreSQL、MongoDB；phpMyAdmin 和 Adminer |
| PHP、多 PHP、扩展与 Composer | 已实现，但有缺口 | 当前受支持的 PHP 8.2-8.5 分支、并行 FPM、Composer、可选扩展、固定版本的额外 PECL 扩展和私有二进制注入点 |
| Java/Tomcat 与 Node.js | 已实现 | Tomcat 9/10/11 使用 Docker Official Image 提供的 Temurin 8/11/17/21/25 LTS 变体，另支持 Node.js |
| Redis、Memcached 与 Pure-FTPd | 已实现 | Redis 持久化、Memcached 隔离和 FTPS 虚拟用户 |
| TLS 证书生命周期 | 已实现，需外部验收 | Caddy 自动 HTTPS、Certbot HTTP-01、续期、自签名证书、FTPS 重载和宿主机 systemd 定时器 |
| 备份与恢复 | 已实现 | Web、配置、Tomcat、NPM、APISIX etcd 快照、FTP 及所有数据库类型；原子化校验和集、可选 age 加密与 rclone 副本 |
| 升级、卸载与日常管理 | 已实现 | 构建/更新、健康等待、安全停止/清理，以及需单独确认且由标记保护的数据清除 |
| 安全与诊断 | 已实现，需外部验收 | 共享内部后端、运行时出站隔离、文件密钥、资源/PID 上限、日志轮转、TLS 优先的 FTP 和健康检查 |

## 明确保留的缺口

- 停止支持的 PHP、Tomcat 和数据库版本不再作为受维护选项。PHP 跟随
  php.net 当前支持分支，MySQL 仅接受 LTS 轨道，开源 JDK 跟随 Temurin LTS 可用性。
- 不再分发专有 PHP 加载器。可通过 `php/custom` 提供 ABI 匹配的厂商模块，其许可
  合规由部署者负责。Gmagick 未内置，因为其最新 PECL 版本仍是发布候选版。
- 不提供缺少持续维护上游容器镜像来源的 JDK 发行版。仍受维护的 Temurin LTS
  均可选择，Temurin 25 是默认 JDK。
- 已实现 Certbot HTTP-01 和 Caddy 自动 HTTPS。管理器不会配置各云服务商专用的
  DNS 验证插件。
- 备份可复制到任意已配置的 rclone 远程端，但不提供针对各云厂商的交互式向导，
  也没有备份专用的宿主机定时器。证书续期具有明确的 systemd 定时器。
- Fail2ban、SSH 端口修改、防火墙规则和重启属于宿主机/平台职责。容器健康检查和
  网络隔离仅替代其中具有有效容器等价实现的部分。

不以与历史安装器原始命令行选项逐项一致作为发布就绪度评分。发布就绪度取决于
下方的验收证据。

## 验证状态

已检查 Shell 语法、ShellCheck、Compose 渲染、构建上下文、配置事务、站点渲染、NPM 和 APISIX 启动、
密钥生成、显式宿主机数据根目录初始化、备份归档恢复和本地生命周期行为。
`tests/runtime.sh` 定义 Docker Linux 默认技术栈验收，`.github/workflows/ci.yml`
会在 CI 中运行它。在该工作流通过之前，镜像构建和服务启动仍未完成验收。
数据库恢复、age 加密恢复、systemd 定时器激活、FTPS 传输、其他可选技术栈类型、
公网 ACME 签发仍需要在指定范围内使用启用 Docker 的 Linux 环境进行验收。
