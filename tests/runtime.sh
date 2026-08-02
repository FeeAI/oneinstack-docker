#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

DOCKER_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/oneinstack-runtime.XXXXXX)"
ENV_FILE="${TEST_ROOT}/stack.env"
DATA_DIR="${TEST_ROOT}/data"
MANAGER=("${DOCKER_DIR}/oneinstack" --env-file "${ENV_FILE}")
KEEP_RUNTIME_DATA="${KEEP_RUNTIME_DATA:-0}"
HTTP_PORT="${ONEINSTACK_TEST_HTTP_PORT:-18080}"
HTTPS_PORT="${ONEINSTACK_TEST_HTTPS_PORT:-18443}"
HTTP_RESPONSE=""

# shellcheck source=../scripts/env.sh
# shellcheck disable=SC1091
source "${DOCKER_DIR}/scripts/env.sh"

cleanup() {
  local exit_code=$?
  local cleanup_image="oneinstack/mysql:9.7"

  if [[ -f "${ENV_FILE}" ]]; then
    cleanup_image="oneinstack/mysql:$(env_get "${ENV_FILE}" MYSQL_VERSION 9.7)"
    if ((exit_code != 0)); then
      "${MANAGER[@]}" ps >&2 || true
      "${MANAGER[@]}" compose logs --no-color --tail=120 >&2 || true
    fi
    "${MANAGER[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
  if [[ "${KEEP_RUNTIME_DATA}" == "1" ]]; then
    printf '[runtime] Preserved test data: %s\n' "${TEST_ROOT}" >&2
  else
    if ! rm -rf -- "${TEST_ROOT}" 2>/dev/null; then
      if docker image inspect "${cleanup_image}" >/dev/null 2>&1; then
        docker run --rm --entrypoint sh \
          --volume "${TEST_ROOT}:/cleanup" "${cleanup_image}" \
          -c 'rm -rf /cleanup/* /cleanup/.[!.]* /cleanup/..?*' >/dev/null 2>&1 ||
          true
      fi
      if ! rm -rf -- "${TEST_ROOT}" 2>/dev/null; then
        printf '[runtime] Could not remove test data: %s\n' "${TEST_ROOT}" >&2
        if ((exit_code == 0)); then
          exit_code=1
        fi
      fi
    fi
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 ||
  { printf '[runtime] Docker CLI is required.\n' >&2; exit 1; }
docker info >/dev/null 2>&1 ||
  { printf '[runtime] Docker daemon is not reachable.\n' >&2; exit 1; }
docker compose version >/dev/null 2>&1 ||
  { printf '[runtime] Docker Compose v2 is required.\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 ||
  { printf '[runtime] curl is required.\n' >&2; exit 1; }

"${MANAGER[@]}" init --data-dir "${DATA_DIR}"
env_set "${ENV_FILE}" COMPOSE_PROJECT_NAME "oneinstack-runtime-${$}"
env_set "${ENV_FILE}" RESOURCE_PROFILE custom
env_set "${ENV_FILE}" HTTP_BIND 127.0.0.1
env_set "${ENV_FILE}" HTTP_PORT "${HTTP_PORT}"
env_set "${ENV_FILE}" HTTPS_BIND 127.0.0.1
env_set "${ENV_FILE}" HTTPS_PORT "${HTTPS_PORT}"
env_set "${ENV_FILE}" DATABASE_MEMORY_LIMIT 1g

"${MANAGER[@]}" doctor
"${MANAGER[@]}" config --quiet
"${MANAGER[@]}" up

HTTP_RESPONSE="$(
  curl --fail --silent --show-error "http://127.0.0.1:${HTTP_PORT}/healthz"
)"
[[ "${HTTP_RESPONSE}" == "ok" ]] ||
  { printf '[runtime] Unexpected health response: %s\n' "${HTTP_RESPONSE}" >&2; exit 1; }
HTTP_RESPONSE="$(
  curl --fail --silent --show-error "http://127.0.0.1:${HTTP_PORT}/"
)"
grep -q '^OneinStack Docker is running\.$' <<<"${HTTP_RESPONSE}" ||
  { printf '[runtime] Unexpected home response: %s\n' "${HTTP_RESPONSE}" >&2; exit 1; }

"${MANAGER[@]}" php-ext verify
"${MANAGER[@]}" compose exec -T mysql sh -c \
  'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" mysql -uroot --batch --skip-column-names -e "SELECT 1"' |
  grep -q '^1$'
"${MANAGER[@]}" compose exec -T mysql sh -c \
  'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" mysql -uroot "$MYSQL_DATABASE" -e "CREATE TABLE runtime_acceptance (id INT PRIMARY KEY); INSERT INTO runtime_acceptance VALUES (1)"'

"${MANAGER[@]}" backup create
BACKUP_DIR="$(
  find "${DATA_DIR}/backups" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' \
    -exec test -f '{}/database-mysql.sql.gz' \; -print -quit
)"
[[ -n "${BACKUP_DIR}" ]]
"${MANAGER[@]}" compose exec -T mysql sh -c \
  'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" mysql -uroot "$MYSQL_DATABASE" -e "DROP TABLE runtime_acceptance"'
"${MANAGER[@]}" backup restore-db \
  "${BACKUP_DIR}/database-mysql.sql.gz" --yes
"${MANAGER[@]}" compose exec -T mysql sh -c \
  'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" mysql -uroot "$MYSQL_DATABASE" --batch --skip-column-names -e "SELECT COUNT(*) FROM runtime_acceptance"' |
  grep -q '^1$'

"${MANAGER[@]}" restart
"${MANAGER[@]}" up
HTTP_RESPONSE="$(
  curl --fail --silent --show-error "http://127.0.0.1:${HTTP_PORT}/healthz"
)"
[[ "${HTTP_RESPONSE}" == "ok" ]] ||
  { printf '[runtime] Unexpected health response after restart: %s\n' "${HTTP_RESPONSE}" >&2; exit 1; }

docker image inspect \
  oneinstack/php:8.5 \
  oneinstack/nginx:1.30.4 \
  oneinstack/mysql:9.7 \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}'

"${MANAGER[@]}" down --remove-orphans
"${MANAGER[@]}" configure --web npm
env_set "${ENV_FILE}" NPM_ADMIN_BIND 127.0.0.1
env_set "${ENV_FILE}" NPM_ADMIN_PORT 18081
"${MANAGER[@]}" up
curl --fail --silent --show-error "http://127.0.0.1:18081/" >/dev/null

"${MANAGER[@]}" down --remove-orphans
"${MANAGER[@]}" configure --web nginx --enable apisix
env_set "${ENV_FILE}" APISIX_HTTP_BIND 127.0.0.1
env_set "${ENV_FILE}" APISIX_HTTP_PORT 19080
env_set "${ENV_FILE}" APISIX_HTTPS_BIND 127.0.0.1
env_set "${ENV_FILE}" APISIX_HTTPS_PORT 19443
env_set "${ENV_FILE}" APISIX_ADMIN_BIND 127.0.0.1
env_set "${ENV_FILE}" APISIX_ADMIN_PORT 19180
"${MANAGER[@]}" up

curl --fail --silent --show-error "http://127.0.0.1:19180/ui/" >/dev/null
APISIX_ADMIN_KEY="$(cat "$(env_get "${ENV_FILE}" APISIX_ADMIN_KEY_FILE)")"
curl --fail --silent --show-error --request PUT \
  --header "X-API-KEY: ${APISIX_ADMIN_KEY}" \
  --header 'Content-Type: application/json' \
  --data '{"uri":"/healthz","upstream":{"type":"roundrobin","nodes":{"nginx:80":1}}}' \
  "http://127.0.0.1:19180/apisix/admin/routes/runtime-health" >/dev/null
curl --fail --silent --show-error "http://127.0.0.1:19080/healthz" | grep -q '^ok$'

"${MANAGER[@]}" backup create
APISIX_BACKUP="$(find "${DATA_DIR}/backups" -mindepth 2 -maxdepth 2 \
  -type f -name 'apisix-etcd.snapshot.db' -print | sort | tail -1)"
[[ -n "${APISIX_BACKUP}" ]]
curl --fail --silent --show-error --request DELETE \
  --header "X-API-KEY: ${APISIX_ADMIN_KEY}" \
  "http://127.0.0.1:19180/apisix/admin/routes/runtime-health" >/dev/null
"${MANAGER[@]}" backup restore-apisix "${APISIX_BACKUP}" --yes
"${MANAGER[@]}" up
curl --fail --silent --show-error "http://127.0.0.1:19080/healthz" | grep -q '^ok$'
docker image inspect \
  oneinstack/apisix:3.17.0-debian \
  gcr.io/etcd-development/etcd:v3.6.11 \
  --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}'

printf 'OneinStack Docker runtime acceptance passed.\n'
