#!/usr/bin/env bash
set -Eeuo pipefail

DOCKER_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${DOCKER_DIR}"
TEST_DIR="$(mktemp -d /tmp/oneinstack-docker-test.XXXXXX)"
TEST_ENV="${TEST_DIR}/stack.env"
TEST_DATA_DIR="${TEST_DIR}/host-data"

# shellcheck source=../scripts/env.sh
# shellcheck disable=SC1091
source "${DOCKER_DIR}/scripts/env.sh"

cleanup() {
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT
trap 'printf "Static check failed at line %s.\n" "${LINENO}" >&2' ERR

test_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

test_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

bash -n \
  "${DOCKER_DIR}/oneinstack" \
  "${DOCKER_DIR}/scripts/env.sh" \
  "${DOCKER_DIR}/scripts/site.sh" \
  "${DOCKER_DIR}/scripts/backup.sh" \
  "${DOCKER_DIR}/scripts/cert-renew-timer.sh" \
  "${DOCKER_DIR}/tests/runtime.sh" \
  "${DOCKER_DIR}/tests/static.sh"

sh -n \
  "${DOCKER_DIR}/php/fpm-healthcheck" \
  "${DOCKER_DIR}/php/install-extensions" \
  "${DOCKER_DIR}/php/secrets-entrypoint" \
  "${DOCKER_DIR}/node/secrets-entrypoint" \
  "${DOCKER_DIR}/tomcat/secrets-entrypoint" \
  "${DOCKER_DIR}/mariadb/secrets-entrypoint" \
  "${DOCKER_DIR}/percona/secrets-entrypoint" \
  "${DOCKER_DIR}/postgresql/secrets-entrypoint" \
  "${DOCKER_DIR}/mongodb/secrets-entrypoint" \
  "${DOCKER_DIR}/apisix/secrets-entrypoint" \
  "${DOCKER_DIR}/ftp/entrypoint" \
  "${DOCKER_DIR}/ftp/manage-user"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S style \
    "${DOCKER_DIR}/oneinstack" \
    "${DOCKER_DIR}/scripts/env.sh" \
    "${DOCKER_DIR}/scripts/site.sh" \
    "${DOCKER_DIR}/scripts/backup.sh" \
    "${DOCKER_DIR}/scripts/cert-renew-timer.sh" \
    "${DOCKER_DIR}/tests/runtime.sh" \
    "${DOCKER_DIR}/tests/static.sh" \
    "${DOCKER_DIR}/php/fpm-healthcheck" \
    "${DOCKER_DIR}/php/install-extensions" \
    "${DOCKER_DIR}/php/secrets-entrypoint" \
    "${DOCKER_DIR}/node/secrets-entrypoint" \
    "${DOCKER_DIR}/tomcat/secrets-entrypoint" \
    "${DOCKER_DIR}/mariadb/secrets-entrypoint" \
    "${DOCKER_DIR}/percona/secrets-entrypoint" \
    "${DOCKER_DIR}/postgresql/secrets-entrypoint" \
    "${DOCKER_DIR}/mongodb/secrets-entrypoint" \
    "${DOCKER_DIR}/apisix/secrets-entrypoint" \
    "${DOCKER_DIR}/ftp/entrypoint" \
    "${DOCKER_DIR}/ftp/manage-user"
fi

if command -v ruby >/dev/null 2>&1; then
  ruby - "${DOCKER_DIR}" <<'RUBY'
require "yaml"

docker_dir = ARGV.fetch(0)
compose = YAML.safe_load(
  File.read(File.join(docker_dir, "compose.yaml")),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: true
)
services = compose.fetch("services")
abort "expected at least 20 services" unless services.size >= 20

services.each do |name, service|
  abort "missing log rotation for #{name}" unless service.dig("logging", "options", "max-size")
  abort "missing memory limit for #{name}" unless service["mem_limit"]
  abort "missing CPU limit for #{name}" unless service["cpus"]
  abort "missing PID limit for #{name}" unless service["pids_limit"]

  next unless service["build"]

  build = service.fetch("build")
  context = build.is_a?(String) ? build : build.fetch("context")
  dockerfile = File.join(docker_dir, context.sub(%r{\A\./}, ""), "Dockerfile")
  abort "missing build context for #{name}: #{dockerfile}" unless File.file?(dockerfile)
end

%w[nginx tengine openresty caddy apache].each do |name|
  condition = services.dig(name, "depends_on", "php", "condition")
  abort "#{name} must wait for healthy PHP" unless condition == "service_healthy"
end

tomcat = services.fetch("tomcat")
tomcat_build = tomcat.fetch("build")
abort "Tomcat must use its fixed Dockerfile" if tomcat_build.key?("dockerfile")
expected_tomcat_args = {
  "TOMCAT_VERSION" => "${TOMCAT_VERSION:-11.0}",
  "JDK_VERSION" => "${JDK_VERSION:-25}",
  "TOMCAT_BASE_IMAGE" => "${TOMCAT_BASE_IMAGE:-tomcat:${TOMCAT_VERSION:-11.0}-jdk${JDK_VERSION:-25}-temurin}"
}
abort "unexpected Tomcat build arguments" unless tomcat_build.fetch("args") == expected_tomcat_args
expected_tomcat_image = "oneinstack/tomcat:${TOMCAT_IMAGE_TAG:-${TOMCAT_VERSION:-11.0}-temurin-jdk${JDK_VERSION:-25}}"
abort "unexpected Tomcat image name" unless tomcat["image"] == expected_tomcat_image

expected_secrets = %w[
  apisix_admin_key database_password mysql_root_password mongodb_root_password redis_password
]
abort "unexpected Compose secrets" unless compose.fetch("secrets").keys.sort == expected_secrets.sort
expected_secret_files = {
  "database_password" => "${DATABASE_PASSWORD_FILE:?DATABASE_PASSWORD_FILE must be set}",
  "mysql_root_password" => "${MYSQL_ROOT_PASSWORD_FILE:?MYSQL_ROOT_PASSWORD_FILE must be set}",
  "mongodb_root_password" => "${MONGODB_ROOT_PASSWORD_FILE:?MONGODB_ROOT_PASSWORD_FILE must be set}",
  "redis_password" => "${REDIS_PASSWORD_FILE:?REDIS_PASSWORD_FILE must be set}",
  "apisix_admin_key" => "${APISIX_ADMIN_KEY_FILE:?APISIX_ADMIN_KEY_FILE must be set}"
}
expected_secret_files.each do |name, expected|
  actual = compose.dig("secrets", name, "file")
  abort "unexpected host secret source for #{name}" unless actual == expected
end
expected_service_secrets = {
  %w[php php82 php83 php84 php85] => %w[database_password redis_password],
  %w[mysql mariadb percona] => %w[database_password mysql_root_password],
  %w[postgresql node tomcat] => %w[database_password],
  %w[mongodb] => %w[database_password mongodb_root_password],
  %w[redis] => %w[redis_password],
  %w[apisix] => %w[apisix_admin_key]
}
expected_service_secrets.each do |names, expected|
  names.each do |name|
    actual = Array(services.fetch(name)["secrets"])
    abort "unexpected secrets for #{name}: #{actual.inspect}" unless actual.sort == expected.sort
  end
end

expected_networks = {
  %w[nginx tengine openresty caddy apache npm apisix] => %w[frontend backend],
  %w[php php82 php83 php84 php85 node tomcat] => %w[backend egress],
  %w[mysql mariadb percona postgresql mongodb redis memcached apisix-etcd] => %w[backend],
  %w[phpmyadmin adminer] => %w[frontend backend],
  %w[certbot ftp] => %w[frontend]
}
expected_networks.each do |names, expected|
  names.each do |name|
    actual = Array(services.fetch(name)["networks"])
    abort "unexpected networks for #{name}: #{actual.inspect}" unless actual == expected
  end
end

npm = services.fetch("npm")
abort "unexpected NPM image" unless npm["image"] == "jc21/nginx-proxy-manager:${NPM_VERSION:-2.15.1}"
abort "NPM must use its packaged health check" unless npm.dig("healthcheck", "test") == ["CMD", "/usr/bin/check-health"]
abort "NPM must be isolated behind its web profile" unless npm["profiles"] == ["web-npm"]
expected_npm_admin_port = "${NPM_ADMIN_BIND:-127.0.0.1}:${NPM_ADMIN_PORT:-81}:81"
abort "NPM admin UI must bind to loopback by default" unless npm.fetch("ports").include?(expected_npm_admin_port)

apisix = services.fetch("apisix")
abort "unexpected APISIX image" unless apisix["image"] == "oneinstack/apisix:${APISIX_VERSION:-3.17.0-debian}"
abort "APISIX must use its feature profile" unless apisix["profiles"] == ["feature-apisix"]
abort "APISIX must wait for healthy etcd" unless apisix.dig("depends_on", "apisix-etcd", "condition") == "service_healthy"
expected_apisix_admin_port = "${APISIX_ADMIN_BIND:-127.0.0.1}:${APISIX_ADMIN_PORT:-9180}:9180"
abort "APISIX Admin API must bind to loopback by default" unless apisix.fetch("ports").include?(expected_apisix_admin_port)
etcd = services.fetch("apisix-etcd")
abort "unexpected etcd image" unless etcd["image"] == "gcr.io/etcd-development/etcd:${ETCD_VERSION:-v3.6.11}"
abort "APISIX etcd must not publish host ports" if etcd.key?("ports")
abort "APISIX etcd must use its feature profile" unless etcd["profiles"] == ["feature-apisix"]

networks = compose.fetch("networks")
abort "backend network must use the bridge driver" unless networks.dig("backend", "driver") == "bridge"
abort "backend network must be internal" unless networks.dig("backend", "internal") == true
abort "backend network must be attachable" unless networks.dig("backend", "attachable") == true
abort "runtime egress network must use bridge" unless networks.dig("egress", "driver") == "bridge"
RUBY
fi

[[ -f "${DOCKER_DIR}/tomcat/Dockerfile" ]]
grep -Fq 'ENTRYPOINT ["oneinstack-secrets-entrypoint"]' \
  "${DOCKER_DIR}/tomcat/Dockerfile"
grep -Fq 'CMD ["catalina.sh", "run"]' "${DOCKER_DIR}/tomcat/Dockerfile"
[[ -f "${DOCKER_DIR}/apisix/Dockerfile" ]]
grep -Fq "key: \${{APISIX_ADMIN_KEY}}" "${DOCKER_DIR}/apisix/config.yaml"
grep -Fq 'http://apisix-etcd:2379' "${DOCKER_DIR}/apisix/config.yaml"
grep -Fq '  user: apisix' "${DOCKER_DIR}/apisix/config.yaml"
grep -Fq 'apt-get install --yes --no-install-recommends curl libxml2 libxslt1.1' \
  "${DOCKER_DIR}/apisix/Dockerfile"
grep -Fq 'rm -f /etc/apt/sources.list.d/apisix.list' \
  "${DOCKER_DIR}/apisix/Dockerfile"
grep -Fq 'test: ["CMD", "curl", "--fail", "--silent", "http://127.0.0.1:7085/status/ready"]' \
  "${DOCKER_DIR}/compose.yaml"
if grep -Eq 'key: [a-zA-Z0-9_-]{16,}$' "${DOCKER_DIR}/apisix/config.yaml"; then
  printf 'APISIX configuration contains a hardcoded Admin API key.\n' >&2
  exit 1
fi
grep -q 'TENGINE_SHA256' "${DOCKER_DIR}/tengine/Dockerfile"
grep -q 'sha256sum -c' "${DOCKER_DIR}/tengine/Dockerfile"
grep -Fq 'extension_loaded("Zend OPcache")' "${DOCKER_DIR}/php/Dockerfile"
grep -Fq "docker-php-ext-install -j\"\$(nproc)\" opcache" \
  "${DOCKER_DIR}/php/Dockerfile"
for web_dockerfile in nginx openresty tengine; do
  grep -q 'fastcgi_pass 127.0.0.1:9000' \
    "${DOCKER_DIR}/${web_dockerfile}/Dockerfile"
  grep -q 'mv /tmp/default.conf' "${DOCKER_DIR}/${web_dockerfile}/Dockerfile"
done
grep -q 'set -- "\$@" -Y 3 -2' "${DOCKER_DIR}/ftp/entrypoint"
grep -q "chown -R mysql:mysql /var/lib/mysql" \
  "${DOCKER_DIR}/percona/secrets-entrypoint"
grep -q 'setpriv --reuid=mysql --regid=mysql' "${DOCKER_DIR}/percona/secrets-entrypoint"
grep -q -- '--set-gtid-purged=OFF' "${DOCKER_DIR}/scripts/backup.sh"

# Match the literal default-path expression in the manager source.
# shellcheck disable=SC2016
grep -Fq 'DEFAULT_DATA_DIR="${ONEINSTACK_DEFAULT_DATA_DIR:-${SCRIPT_DIR}/data}"' \
  "${DOCKER_DIR}/oneinstack"

if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_DIR}/unsafe.env" \
  init --data-dir /opt >/dev/null 2>&1; then
  printf 'Unsafe host data directory was accepted.\n' >&2
  exit 1
fi

MAIN_HELP="$("${DOCKER_DIR}/oneinstack" --help)"
CONFIGURE_HELP="$(ONEINSTACK_ENV_FILE="${TEST_DIR}/missing.env" \
  "${DOCKER_DIR}/oneinstack" configure -h)"
readme_configure_help() {
  awk '
    /<!-- oneinstack-configure-help:start -->/ { printing = 1; next }
    /<!-- oneinstack-configure-help:end -->/ { printing = 0 }
    printing && /^```text$/ { next }
    printing && /^```$/ { next }
    printing { print }
  ' "$1"
}
for readme in "${DOCKER_DIR}/README.md" "${DOCKER_DIR}/README.zh-CN.md"; do
  if [[ "$(readme_configure_help "${readme}")" != "${CONFIGURE_HELP}" ]]; then
    printf 'Documented configure help is out of sync: %s\n' "${readme}" >&2
    exit 1
  fi
done
grep -q '^Usage:$' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--db ENGINE[:VERSION]' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--redis VERSION' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--apisix VERSION' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--memcached VERSION' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--phpmyadmin VERSION' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--adminer VERSION' <<<"${CONFIGURE_HELP}"
grep -Fq 'Every configure version option accepts latest.' <<<"${CONFIGURE_HELP}"
grep -Fq 'preserving required FPM/Alpine/slim variants.' <<<"${CONFIGURE_HELP}"
grep -Fq -- '--ftp-tls-mode MODE' <<<"${CONFIGURE_HELP}"
for help_output in "${MAIN_HELP}" "${CONFIGURE_HELP}"; do
  grep -Fq './oneinstack configure --redis 8.8 --memcached 1.6' <<<"${help_output}"
  grep -Fq './oneinstack configure --node 24 --tomcat 11.0 --jdk 25' <<<"${help_output}"
  grep -Fq './oneinstack configure --phpmyadmin 5-apache --adminer 5-standalone' <<<"${help_output}"
  grep -Fq './oneinstack configure --apisix 3.17.0-debian' <<<"${help_output}"
done
if grep -qi 'oracle' <<<"${CONFIGURE_HELP}"; then
  printf 'Removed Oracle JDK options remain in configure help.\n' >&2
  exit 1
fi
cmp <("${DOCKER_DIR}/oneinstack" configure --help) \
  <("${DOCKER_DIR}/oneinstack" help configure)

mkdir -p "${TEST_DIR}/nonempty-data"
touch "${TEST_DIR}/nonempty-data/unrelated"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_DIR}/nonempty.env" \
  init --data-dir "${TEST_DIR}/nonempty-data" >/dev/null 2>&1; then
  printf 'A non-empty unmarked host data directory was adopted.\n' >&2
  exit 1
fi

ONEINSTACK_DEFAULT_DATA_DIR="${TEST_DATA_DIR}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" init >/dev/null
TEST_DATA_DIR="$(CDPATH='' cd -- "${TEST_DATA_DIR}" && pwd -P)"
[[ "$(test_mode "${TEST_ENV}")" == "600" ]]
grep -q '^COMPOSE_PROFILES=web-nginx,db-mysql$' "${TEST_ENV}"
grep -q '^WEB_ENGINE=nginx$' "${TEST_ENV}"
grep -q '^DATABASE_ENGINE=mysql$' "${TEST_ENV}"
grep -q '^MYSQL_VERSION=9.7$' "${TEST_ENV}"
grep -q '^PHP_VERSION=8.5$' "${TEST_ENV}"
grep -q '^MARIADB_VERSION=11.8$' "${TEST_ENV}"
grep -q '^MONGODB_VERSION=8.3$' "${TEST_ENV}"
grep -q '^JDK_VERSION=25$' "${TEST_ENV}"
grep -q '^NODE_VERSION=24$' "${TEST_ENV}"
grep -q "^ONEINSTACK_DATA_DIR=${TEST_DATA_DIR}$" "${TEST_ENV}"
grep -q "^DATABASE_PASSWORD_FILE=${TEST_DATA_DIR}/secrets/database_password$" "${TEST_ENV}"
grep -q "^MYSQL_ROOT_PASSWORD_FILE=${TEST_DATA_DIR}/secrets/mysql_root_password$" "${TEST_ENV}"
grep -q "^MONGODB_ROOT_PASSWORD_FILE=${TEST_DATA_DIR}/secrets/mongodb_root_password$" "${TEST_ENV}"
grep -q "^REDIS_PASSWORD_FILE=${TEST_DATA_DIR}/secrets/redis_password$" "${TEST_ENV}"
grep -q "^APISIX_ADMIN_KEY_FILE=${TEST_DATA_DIR}/secrets/apisix_admin_key$" "${TEST_ENV}"
grep -q '^BACKUP_RETENTION_DAYS=180$' "${TEST_ENV}"
grep -q '^oneinstack-data-v1$' "${TEST_DATA_DIR}/.oneinstack-managed"
[[ -f "${TEST_DATA_DIR}/www/default/index.php" ]]
[[ -f "${TEST_DATA_DIR}/tomcat/webapps/ROOT/index.jsp" ]]
[[ -f "${TEST_DATA_DIR}/config/nginx/default.conf" ]]
[[ -d "${TEST_DATA_DIR}/mysql" ]]
[[ -d "${TEST_DATA_DIR}/npm/data" ]]
[[ -d "${TEST_DATA_DIR}/npm/letsencrypt" ]]
[[ -d "${TEST_DATA_DIR}/apisix/etcd" ]]
[[ "$(test_mode "${TEST_DATA_DIR}/apisix/etcd")" == "700" ]]
[[ -d "${TEST_DATA_DIR}/backups" ]]
if grep -Eq 'change-me-(app|root|redis|mongodb)' "${TEST_ENV}"; then
  printf 'Generated environment still contains placeholder credentials.\n' >&2
  exit 1
fi
for secret_name in database_password mysql_root_password mongodb_root_password redis_password apisix_admin_key; do
  secret_file="${TEST_DATA_DIR}/secrets/${secret_name}"
  [[ -s "${secret_file}" ]]
  [[ "$(test_mode "${secret_file}")" == "600" ]]
done
if grep -Eq '^(DATABASE_PASSWORD|MYSQL_ROOT_PASSWORD|MONGODB_ROOT_PASSWORD|REDIS_PASSWORD|APISIX_ADMIN_KEY)=.+' \
  "${TEST_ENV}"; then
  printf 'Generated environment contains an inline service password.\n' >&2
  exit 1
fi

SECRET_STATUS="$("${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" secret list)"
grep -q "^database *configured ${TEST_DATA_DIR}/secrets/database_password$" \
  <<<"${SECRET_STATUS}"
if grep -q "$(cat "${TEST_DATA_DIR}/secrets/database_password")" <<<"${SECRET_STATUS}"; then
  printf 'Secret list exposed a password value.\n' >&2
  exit 1
fi
SHOW_CONFIG="$("${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" show-config)"
grep -q '^Database: *mysql:9.7 (mysql:3306)$' <<<"${SHOW_CONFIG}"
grep -q '^Secret sources:$' <<<"${SHOW_CONFIG}"
grep -q "^redis *configured ${TEST_DATA_DIR}/secrets/redis_password$" \
  <<<"${SHOW_CONFIG}"
grep -q "^apisix *configured ${TEST_DATA_DIR}/secrets/apisix_admin_key$" \
  <<<"${SHOW_CONFIG}"

printf 'configured-database-password\n' |
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
    secret set database --stdin >/dev/null
[[ "$(cat "${TEST_DATA_DIR}/secrets/database_password")" == \
  "configured-database-password" ]]

CUSTOM_REDIS_SECRET="${TEST_DIR}/configured-secrets/redis-password"
mkdir -p "$(dirname -- "${CUSTOM_REDIS_SECRET}")"
chmod 0755 "$(dirname -- "${CUSTOM_REDIS_SECRET}")"
printf 'configured-redis-password\n' |
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
    secret set redis --path "${CUSTOM_REDIS_SECRET}" --stdin >/dev/null
[[ "$(cat "${CUSTOM_REDIS_SECRET}")" == "configured-redis-password" ]]
[[ "$(test_mode "$(dirname -- "${CUSTOM_REDIS_SECRET}")")" == "755" ]]
grep -q "^REDIS_PASSWORD_FILE=${CUSTOM_REDIS_SECRET}$" "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db mysql:8.4.10 >/dev/null
grep -q '^DATABASE_ENGINE=mysql$' "${TEST_ENV}"
grep -q '^MYSQL_VERSION=8.4.10$' "${TEST_ENV}"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db mysql >/dev/null
grep -q '^MYSQL_VERSION=8.4.10$' "${TEST_ENV}"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db mysql:9.7 >/dev/null
grep -q '^MYSQL_VERSION=9.7$' "${TEST_ENV}"

for database_case in \
  mariadb:10.11:MARIADB_VERSION \
  mariadb:11.4.5-noble:MARIADB_VERSION \
  mariadb:11.8:MARIADB_VERSION \
  percona:8.4.6-6.1:PERCONA_VERSION \
  postgresql:15:POSTGRES_VERSION \
  postgresql:16.4-alpine:POSTGRES_VERSION \
  postgresql:17:POSTGRES_VERSION \
  postgresql:18:POSTGRES_VERSION \
  mongodb:7.0:MONGODB_VERSION \
  mongodb:8.0.14-noble:MONGODB_VERSION \
  mongodb:8.3:MONGODB_VERSION; do
  database_spec="${database_case%:*}"
  version_key="${database_case##*:}"
  database_version="${database_spec#*:}"
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
    configure --db "${database_spec}" >/dev/null
  grep -q "^${version_key}=${database_version}$" "${TEST_ENV}"
done

cp "${TEST_ENV}" "${TEST_ENV}.before"
for invalid_database in \
  mysql: mysql:8.0 mysql:9.6 mysql:9.7@sha \
  mariadb:10.6 mariadb:12.3 \
  percona:8.0 percona:9.7 \
  postgresql:14 postgresql:19beta2 \
  mongodb:6.0 mongodb:8.2 none:1; do
  if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
    configure --db "${invalid_database}" >/dev/null 2>&1; then
    printf 'Invalid database version was accepted: %s\n' "${invalid_database}" >&2
    exit 1
  fi
  cmp "${TEST_ENV}" "${TEST_ENV}.before"
done

mkdir -p "${TEST_DIR}/future-date-bin"
# Keep positional parameters literal for the generated date fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "$1" = "-u" ] && [ "$2" = "+%F" ]; then' \
  '  printf "%s\\n" 2028-05-30' \
  'else' \
  '  exec /bin/date "$@"' \
  'fi' \
  >"${TEST_DIR}/future-date-bin/date"
chmod 0755 "${TEST_DIR}/future-date-bin/date"
cp "${TEST_ENV}" "${TEST_ENV}.before"
if PATH="${TEST_DIR}/future-date-bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db mariadb:11.4 >/dev/null 2>&1; then
  printf 'A database track below the one-year maintenance threshold was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

cp "${TEST_ENV}" "${TEST_ENV}.before"
env_set "${TEST_ENV}" DATABASE_ENGINE mariadb
env_set "${TEST_ENV}" MARIADB_VERSION 10.6
unsupported_database_output="$(
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" config --quiet 2>&1 || true
)"
grep -q 'MariaDB must use a maintained' <<<"${unsupported_database_output}"
mv "${TEST_ENV}.before" "${TEST_ENV}"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --php 8.1 >/dev/null 2>&1; then
  printf 'Unsupported PHP 8.1 was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

cp "${TEST_ENV}" "${TEST_ENV}.unsupported-php"
env_set "${TEST_ENV}" PHP_VERSION 8.1
unsupported_php_output="$(
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" config --quiet 2>&1 || true
)"
grep -q 'Supported PHP versions are 8.2, 8.3, 8.4 and 8.5.' \
  <<<"${unsupported_php_output}"
env_set "${TEST_ENV}" PHP_VERSION 8.4
env_set "${TEST_ENV}" ADDITIONAL_PHP 8.1
unsupported_php_output="$(
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" config --quiet 2>&1 || true
)"
grep -q 'Supported PHP versions are 8.2, 8.3, 8.4 and 8.5.' \
  <<<"${unsupported_php_output}"
mv "${TEST_ENV}.unsupported-php" "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db mysql --redis 8.6-alpine --memcached 1.6-alpine \
  --phpmyadmin 5.2-apache --adminer 5-standalone \
  --apisix 3.17.0-debian >/dev/null
grep -q '^REDIS_VERSION=8.6-alpine$' "${TEST_ENV}"
grep -q '^MEMCACHED_VERSION=1.6-alpine$' "${TEST_ENV}"
grep -q '^PHPMYADMIN_VERSION=5.2-apache$' "${TEST_ENV}"
grep -q '^ADMINER_VERSION=5-standalone$' "${TEST_ENV}"
grep -q '^APISIX_VERSION=3.17.0-debian$' "${TEST_ENV}"
grep -q '^ENABLE_REDIS=1$' "${TEST_ENV}"
grep -q '^ENABLE_MEMCACHED=1$' "${TEST_ENV}"
grep -q '^ENABLE_PHPMYADMIN=1$' "${TEST_ENV}"
grep -q '^ENABLE_ADMINER=1$' "${TEST_ENV}"
grep -q '^ENABLE_APISIX=1$' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=.*redis' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=.*memcached' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=.*tools-phpmyadmin' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=.*tools-adminer' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=.*feature-apisix' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" configure \
  --db mysql:latest --php latest --redis latest --memcached latest \
  --node latest --tomcat latest --phpmyadmin latest --adminer latest \
  --apisix latest >/dev/null
grep -q '^MYSQL_VERSION=latest$' "${TEST_ENV}"
grep -q '^PHP_VERSION=latest$' "${TEST_ENV}"
grep -q '^PHP_BASE_IMAGE=php:fpm-bookworm$' "${TEST_ENV}"
grep -q '^REDIS_BASE_IMAGE=redis:alpine$' "${TEST_ENV}"
grep -q '^MEMCACHED_BASE_IMAGE=memcached:alpine$' "${TEST_ENV}"
grep -q '^NODE_BASE_IMAGE=node:bookworm-slim$' "${TEST_ENV}"
grep -q '^TOMCAT_VERSION=latest$' "${TEST_ENV}"
grep -q '^JDK_VERSION=latest$' "${TEST_ENV}"
grep -q '^TOMCAT_BASE_IMAGE=tomcat:latest$' "${TEST_ENV}"
grep -q '^TOMCAT_IMAGE_TAG=latest$' "${TEST_ENV}"
grep -q '^PHPMYADMIN_VERSION=latest$' "${TEST_ENV}"
grep -q '^ADMINER_VERSION=latest$' "${TEST_ENV}"
grep -q '^APISIX_VERSION=latest$' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" configure \
  --db mysql:9.7 --php 8.5 --redis 8.8 --memcached 1.6 --node 24 \
  --tomcat 11.0 --jdk 25 --phpmyadmin 5-apache \
  --adminer 5-standalone --apisix 3.17.0-debian >/dev/null
grep -q '^PHP_BASE_IMAGE=$' "${TEST_ENV}"
grep -q '^REDIS_BASE_IMAGE=$' "${TEST_ENV}"
grep -q '^MEMCACHED_BASE_IMAGE=$' "${TEST_ENV}"
grep -q '^NODE_BASE_IMAGE=$' "${TEST_ENV}"
grep -q '^TOMCAT_BASE_IMAGE=$' "${TEST_ENV}"
grep -q '^TOMCAT_IMAGE_TAG=$' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --jdk latest >/dev/null
grep -q '^TOMCAT_VERSION=latest$' "${TEST_ENV}"
grep -q '^JDK_VERSION=latest$' "${TEST_ENV}"
grep -q '^TOMCAT_BASE_IMAGE=tomcat:latest$' "${TEST_ENV}"
grep -q '^TOMCAT_IMAGE_TAG=latest$' "${TEST_ENV}"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 11.0 --jdk 25 >/dev/null

cp "${TEST_ENV}" "${TEST_ENV}.before"
for invalid_option in redis memcached phpmyadmin adminer apisix; do
  if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
    configure "--${invalid_option}" '8.0@sha' >/dev/null 2>&1; then
    printf 'Invalid %s version was accepted.\n' "${invalid_option}" >&2
    exit 1
  fi
  cmp "${TEST_ENV}" "${TEST_ENV}.before"
done
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --disable phpmyadmin,adminer >/dev/null
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --web npm >/dev/null
grep -q '^WEB_ENGINE=npm$' "${TEST_ENV}"
grep -q '^COMPOSE_PROFILES=web-npm,' "${TEST_ENV}"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  site add npm.example.com --runtime proxy --target node:3000 >/dev/null 2>&1; then
  printf 'CLI site management was accepted for Nginx Proxy Manager.\n' >&2
  exit 1
fi
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  tls renew >/dev/null 2>&1; then
  printf 'Certbot renewal was accepted for Nginx Proxy Manager.\n' >&2
  exit 1
fi
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --web nginx >/dev/null
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  secret set redis --path /etc/passwd --generate >/dev/null 2>&1; then
  printf 'An unsafe secret target was accepted.\n' >&2
  exit 1
fi

rm "${TEST_DATA_DIR}/secrets/database_password"
env_set "${TEST_ENV}" DATABASE_PASSWORD 'legacy-$-password'
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" show-config >/dev/null
[[ "$(cat "${TEST_DATA_DIR}/secrets/database_password")" == 'legacy-$-password' ]]
grep -q '^DATABASE_PASSWORD=$' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  php-ext set phalcon,yar,memcache >/dev/null
grep -q '^PHP_EXTENSIONS=phalcon,yar,memcache$' "${TEST_ENV}"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --extensions sqlsrv >/dev/null 2>&1; then
  printf 'sqlsrv was accepted without the Microsoft ODBC EULA.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --extensions sqlsrv --accept-microsoft-eula >/dev/null
grep -q '^MICROSOFT_ODBC_ACCEPT_EULA=Y$' "${TEST_ENV}"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --php 8.2 >/dev/null 2>&1; then
  printf 'sqlsrv was accepted with unsupported PHP 8.2.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --pecl-extra 'uuid@uuid-1.3.0' >/dev/null
cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --pecl-extra 'uuid@latest' >/dev/null 2>&1; then
  printf 'An unpinned extra PECL package was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --enable ftp >/dev/null 2>&1; then
  printf 'FTP was enabled without an FTPS certificate domain.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --enable ftp --ftp-tls-domain ftp.example.com >/dev/null
grep -q '^FTP_TLS_MODE=required$' "${TEST_ENV}"
grep -q '^FTP_TLS_DOMAIN=ftp.example.com$' "${TEST_ENV}"
mkdir -p "${TEST_DIR}/no-docker-bin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"${TEST_DIR}/no-docker-bin/docker"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "Docker is not installed in this test fixture.\\n" >&2' \
  'exit 1' \
  >"${TEST_DIR}/no-docker-bin/docker-compose"
chmod 0755 \
  "${TEST_DIR}/no-docker-bin/docker" \
  "${TEST_DIR}/no-docker-bin/docker-compose"
FTP_UP_ERROR="$(
  PATH="${TEST_DIR}/no-docker-bin:${PATH}" \
    "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" up 2>&1 || true
)"
grep -q 'Generated a self-signed certificate for ftp.example.com' <<<"${FTP_UP_ERROR}"
grep -q 'SHA-256 fingerprint:' <<<"${FTP_UP_ERROR}"
grep -q 'Docker is not installed' <<<"${FTP_UP_ERROR}"
[[ -f "${TEST_DATA_DIR}/certs/live/ftp.example.com/fullchain.pem" ]]
[[ -f "${TEST_DATA_DIR}/certs/live/ftp.example.com/privkey.pem" ]]
[[ "$(test_mode "${TEST_DATA_DIR}/certs/live/ftp.example.com/privkey.pem")" == "600" ]]
if grep -q -- 'BEGIN PRIVATE KEY' <<<"${FTP_UP_ERROR}"; then
  printf 'Automatic FTPS setup printed the private key content.\n' >&2
  exit 1
fi

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  site add static.example.com --runtime static >/dev/null
[[ -f "${TEST_DATA_DIR}/sites/static.example.com.env" ]]
[[ -f "${TEST_DATA_DIR}/config/nginx/static.example.com.conf" ]]
[[ -f "${TEST_DATA_DIR}/www/static.example.com/index.html" ]]
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  tls self-signed static.example.com >/dev/null 2>&1
[[ -f "${TEST_DATA_DIR}/certs/live/static.example.com/fullchain.pem" ]]
grep -q 'listen 443 ssl' "${TEST_DATA_DIR}/config/nginx/static.example.com.conf"

printf 'configuration-original\n' >"${TEST_DATA_DIR}/config/recovery-marker"
printf 'tomcat-original\n' >"${TEST_DATA_DIR}/tomcat/webapps/recovery-marker"
printf 'ftp-original\n' >"${TEST_DATA_DIR}/ftp/recovery-marker"
printf 'npm-original\n' >"${TEST_DATA_DIR}/npm/data/recovery-marker"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --db none --disable apisix >/dev/null
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup create >/dev/null
BACKUP_DIR="$(find "${TEST_DATA_DIR}/backups" -mindepth 1 -maxdepth 1 \
  -type d -name '[0-9]*' -print -quit)"
[[ -n "${BACKUP_DIR}" ]]
[[ -f "${BACKUP_DIR}/webroot.tar.gz" ]]
[[ -f "${BACKUP_DIR}/configuration.tar.gz" ]]
[[ -f "${BACKUP_DIR}/tomcat-webapps.tar.gz" ]]
[[ -f "${BACKUP_DIR}/ftp-state.tar.gz" ]]
[[ -f "${BACKUP_DIR}/npm-state.tar.gz" ]]
[[ -f "${BACKUP_DIR}/SHA256SUMS" ]]
grep -q '^STATUS=complete$' "${BACKUP_DIR}/manifest.env"
grep -q '  webroot.tar.gz$' "${BACKUP_DIR}/SHA256SUMS"
grep -q '  configuration.tar.gz$' "${BACKUP_DIR}/SHA256SUMS"
rm "${TEST_DATA_DIR}/npm/data/recovery-marker"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-npm \
  "${BACKUP_DIR}/npm-state.tar.gz" --yes >/dev/null
grep -q '^npm-original$' "${TEST_DATA_DIR}/npm/data/recovery-marker"
grep -q '  tomcat-webapps.tar.gz$' "${BACKUP_DIR}/SHA256SUMS"
grep -q '  ftp-state.tar.gz$' "${BACKUP_DIR}/SHA256SUMS"
grep -Fq 'compose run --rm --no-deps' "${DOCKER_DIR}/scripts/backup.sh"
grep -Fq 'snapshot save /backup/apisix-etcd.snapshot.db' "${DOCKER_DIR}/scripts/backup.sh"
grep -Fq 'apisix -rf /etcd-data/member' "${DOCKER_DIR}/scripts/backup.sh"
grep -Fq 'etcdutl snapshot restore /snapshot.db' "${DOCKER_DIR}/scripts/backup.sh"
if find "${TEST_DATA_DIR}/backups" -maxdepth 1 -type d -name '.*.partial.*' \
  -print -quit | grep -q .; then
  printf 'A partial backup directory remained after a successful backup.\n' >&2
  exit 1
fi

printf 'configuration-changed\n' >"${TEST_DATA_DIR}/config/recovery-marker"
printf 'tomcat-changed\n' >"${TEST_DATA_DIR}/tomcat/webapps/recovery-marker"
printf 'ftp-changed\n' >"${TEST_DATA_DIR}/ftp/recovery-marker"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-config \
  "${BACKUP_DIR}/configuration.tar.gz" --yes >/dev/null
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-tomcat \
  "${BACKUP_DIR}/tomcat-webapps.tar.gz" --yes >/dev/null
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-ftp \
  "${BACKUP_DIR}/ftp-state.tar.gz" --yes >/dev/null
grep -q '^configuration-original$' "${TEST_DATA_DIR}/config/recovery-marker"
grep -q '^tomcat-original$' "${TEST_DATA_DIR}/tomcat/webapps/recovery-marker"
grep -q '^ftp-original$' "${TEST_DATA_DIR}/ftp/recovery-marker"

cp "${BACKUP_DIR}/manifest.env" "${BACKUP_DIR}/manifest.env.before"
printf 'STATUS=partial\n' >"${BACKUP_DIR}/manifest.env"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-config \
  "${BACKUP_DIR}/configuration.tar.gz" --yes >/dev/null 2>&1; then
  printf 'A backup with a tampered manifest was restored.\n' >&2
  exit 1
fi
mv "${BACKUP_DIR}/manifest.env.before" "${BACKUP_DIR}/manifest.env"

ENGINE_BACKUP_DIR="${TEST_DATA_DIR}/backups/engine-mismatch"
mkdir "${ENGINE_BACKUP_DIR}"
cp "${BACKUP_DIR}/webroot.tar.gz" \
  "${ENGINE_BACKUP_DIR}/database-postgresql.sql.gz"
printf '%s\n' \
  'STATUS=complete' \
  'DATABASE_ENGINE=postgresql' \
  >"${ENGINE_BACKUP_DIR}/manifest.env"
{
  printf '%s  %s\n' \
    "$(test_sha256 "${ENGINE_BACKUP_DIR}/database-postgresql.sql.gz")" \
    database-postgresql.sql.gz
  printf '%s  %s\n' \
    "$(test_sha256 "${ENGINE_BACKUP_DIR}/manifest.env")" \
    manifest.env
} >"${ENGINE_BACKUP_DIR}/SHA256SUMS"
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" configure --db mysql >/dev/null
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-db \
  "${ENGINE_BACKUP_DIR}/database-postgresql.sql.gz" --yes >/dev/null 2>&1; then
  printf 'A backup for another database engine was restored.\n' >&2
  exit 1
fi
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" configure --db none >/dev/null

mkdir "${TEST_DATA_DIR}/backups/.backup.lock"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup create \
  >/dev/null 2>&1; then
  printf 'A concurrent backup lock was ignored.\n' >&2
  exit 1
fi
[[ -d "${TEST_DATA_DIR}/backups/.backup.lock" ]]
rmdir "${TEST_DATA_DIR}/backups/.backup.lock"

printf 'tampered\n' >>"${BACKUP_DIR}/webroot.tar.gz"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-web \
  "${BACKUP_DIR}/webroot.tar.gz" --yes >/dev/null 2>&1; then
  printf 'A backup with a failed checksum was restored.\n' >&2
  exit 1
fi

mkdir -p "${TEST_DIR}/bin"
# The positional parameters belong to the generated age fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'case "$1" in' \
  '  --encrypt)' \
  '    while [ "$1" != "--output" ]; do shift; done' \
  '    output="$2"; input="$3"; cp "$input" "$output"' \
  '    ;;' \
  '  --decrypt)' \
  '    while [ "$#" -gt 1 ]; do shift; done' \
  '    cat "$1"' \
  '    ;;' \
  '  *) exit 2 ;;' \
  'esac' >"${TEST_DIR}/bin/age"
chmod 0755 "${TEST_DIR}/bin/age"
printf 'AGE-SECRET-KEY-TEST\n' >"${TEST_DIR}/age-key.txt"
env_set "${TEST_ENV}" BACKUP_AGE_RECIPIENT age1test
env_set "${TEST_ENV}" BACKUP_AGE_IDENTITY_FILE "${TEST_DIR}/age-key.txt"
PATH="${TEST_DIR}/bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup create >/dev/null
ENCRYPTED_WEB_BACKUP="$(find "${TEST_DATA_DIR}/backups" \
  -name webroot.tar.gz.age -type f -print -quit)"
[[ -n "${ENCRYPTED_WEB_BACKUP}" ]]
grep -q '^ENCRYPTED=1$' "$(dirname -- "${ENCRYPTED_WEB_BACKUP}")/manifest.env"
[[ ! -e "${ENCRYPTED_WEB_BACKUP%.age}" ]]
PATH="${TEST_DIR}/bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" backup restore-web \
  "${ENCRYPTED_WEB_BACKUP}" --yes >/dev/null

TIMER_RENDER="$("${DOCKER_DIR}/scripts/cert-renew-timer.sh" \
  render "${DOCKER_DIR}/oneinstack" "${TEST_ENV}")"
grep -q 'Persistent=true' <<<"${TIMER_RENDER}"
grep -q 'tls renew' <<<"${TIMER_RENDER}"
if grep -q '/var/run/docker.sock' <<<"${TIMER_RENDER}"; then
  printf 'The certificate timer exposes the Docker socket.\n' >&2
  exit 1
fi

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 11.0 --jdk 11 >/dev/null 2>&1; then
  printf 'Temurin below the Tomcat 11 minimum was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 11.0 --jdk 22 >/dev/null 2>&1; then
  printf 'A non-LTS Temurin selection was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

cp "${TEST_ENV}" "${TEST_ENV}.before"
if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 9.0 --jdk 8 --jdk-vendor oracle >/dev/null 2>&1; then
  printf 'Removed Oracle JDK vendor option was accepted.\n' >&2
  exit 1
fi
cmp "${TEST_ENV}" "${TEST_ENV}.before"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 11.0 --jdk 21 >/dev/null
grep -q '^JDK_VERSION=21$' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 10.1 --jdk 11 >/dev/null
grep -q '^JDK_VERSION=11$' "${TEST_ENV}"

"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  configure --tomcat 9.0 --jdk 8 >/dev/null
grep -q '^JDK_VERSION=8$' "${TEST_ENV}"

printf '%s\n' '#!/bin/sh' 'exit 0' >"${TEST_DIR}/bin/docker"
chmod 0755 "${TEST_DIR}/bin/docker"

touch \
  "${TEST_DATA_DIR}/mysql/database.keep" \
  "${TEST_DATA_DIR}/redis/cache.keep" \
  "${TEST_DATA_DIR}/caddy/data/state.keep" \
  "${TEST_DATA_DIR}/npm/data/state.keep" \
  "${TEST_DATA_DIR}/apisix/etcd/state.keep" \
  "${TEST_DATA_DIR}/ftp/credentials.keep" \
  "${TEST_DATA_DIR}/backups/database-mysql.sql.gz" \
  "${TEST_DATA_DIR}/www/site.keep" \
  "${TEST_DATA_DIR}/certs/certificate.keep"

if "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  secret set mysql-root --generate >/dev/null 2>&1; then
  printf 'An in-use database secret was replaced without rotation confirmation.\n' >&2
  exit 1
fi
"${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" \
  secret set mysql-root --generate --after-rotation >/dev/null

PATH="${TEST_DIR}/bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" purge --yes >/dev/null
[[ -f "${TEST_DATA_DIR}/mysql/database.keep" ]]
[[ -f "${TEST_DATA_DIR}/redis/cache.keep" ]]
[[ -f "${TEST_DATA_DIR}/npm/data/state.keep" ]]
[[ -f "${TEST_DATA_DIR}/apisix/etcd/state.keep" ]]
[[ -f "${TEST_DATA_DIR}/backups/database-mysql.sql.gz" ]]
[[ -f "${TEST_DATA_DIR}/www/site.keep" ]]
[[ -f "${TEST_DATA_DIR}/certs/certificate.keep" ]]
[[ -s "${TEST_DATA_DIR}/secrets/database_password" ]]

if PATH="${TEST_DIR}/bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" purge --data \
  >/dev/null 2>&1; then
  printf 'Data purge was accepted without --yes.\n' >&2
  exit 1
fi

PATH="${TEST_DIR}/bin:${PATH}" \
  "${DOCKER_DIR}/oneinstack" --env-file "${TEST_ENV}" purge --data --yes >/dev/null
[[ ! -e "${TEST_DATA_DIR}/mysql/database.keep" ]]
[[ ! -e "${TEST_DATA_DIR}/redis/cache.keep" ]]
[[ ! -e "${TEST_DATA_DIR}/caddy/data/state.keep" ]]
[[ ! -e "${TEST_DATA_DIR}/npm/data/state.keep" ]]
[[ ! -e "${TEST_DATA_DIR}/apisix/etcd/state.keep" ]]
[[ ! -e "${TEST_DATA_DIR}/ftp/credentials.keep" ]]
[[ -d "${TEST_DATA_DIR}/mysql" ]]
[[ -d "${TEST_DATA_DIR}/redis" ]]
[[ -d "${TEST_DATA_DIR}/npm/data" ]]
[[ -d "${TEST_DATA_DIR}/npm/letsencrypt" ]]
[[ -d "${TEST_DATA_DIR}/apisix/etcd" ]]
[[ -f "${TEST_DATA_DIR}/backups/database-mysql.sql.gz" ]]
[[ -f "${TEST_DATA_DIR}/www/site.keep" ]]
[[ -f "${TEST_DATA_DIR}/certs/certificate.keep" ]]

if find "${DOCKER_DIR}" -name .env -type f -print -quit | grep -q .; then
  printf 'A runtime .env file exists inside the project tree.\n' >&2
  exit 1
fi

(
  cd "${REPO_DIR}"
  git diff --check
)

printf 'OneinStack Docker static checks passed.\n'
