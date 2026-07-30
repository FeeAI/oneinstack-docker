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

# shellcheck source=../scripts/env.sh
# shellcheck disable=SC1091
source "${DOCKER_DIR}/scripts/env.sh"

cleanup() {
  local exit_code=$?
  local cleanup_image="oneinstack/mysql:8.4"

  if [[ -f "${ENV_FILE}" ]]; then
    cleanup_image="oneinstack/mysql:$(env_get "${ENV_FILE}" MYSQL_VERSION 8.4)"
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
env_set "${ENV_FILE}" HTTP_BIND 127.0.0.1
env_set "${ENV_FILE}" HTTP_PORT "${HTTP_PORT}"
env_set "${ENV_FILE}" HTTPS_BIND 127.0.0.1
env_set "${ENV_FILE}" HTTPS_PORT "${HTTPS_PORT}"
env_set "${ENV_FILE}" DATABASE_MEMORY_LIMIT 1g

"${MANAGER[@]}" doctor
"${MANAGER[@]}" config --quiet
"${MANAGER[@]}" up

curl --fail --silent --show-error \
  "http://127.0.0.1:${HTTP_PORT}/healthz" |
  grep -q '^ok$'
curl --fail --silent --show-error \
  "http://127.0.0.1:${HTTP_PORT}/" |
  grep -q 'OneinStack Docker stack is running'

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
curl --fail --silent --show-error \
  "http://127.0.0.1:${HTTP_PORT}/healthz" |
  grep -q '^ok$'

docker image inspect \
  oneinstack/php:8.4 \
  oneinstack/nginx:stable \
  oneinstack/mysql:8.4 \
  --format '{{.Id}} {{join .RepoTags ","}} {{join .RepoDigests ","}}'

printf 'OneinStack Docker runtime acceptance passed.\n'
