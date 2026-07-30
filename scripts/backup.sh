#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:?environment file is required}"
shift

# shellcheck source=env.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/env.sh"

MANAGER=("${SCRIPT_DIR}/oneinstack" --env-file "${ENV_FILE}")
DATA_DIR="$(env_get "${ENV_FILE}" ONEINSTACK_DATA_DIR)"
[[ -n "${DATA_DIR}" && "${DATA_DIR}" == /* ]] ||
  { printf '[backup] Error: ONEINSTACK_DATA_DIR must be an absolute path.\n' >&2; exit 1; }
DATA_DIR="${DATA_DIR%/}"
[[ -f "${DATA_DIR}/.oneinstack-managed" ]] &&
  [[ "$(head -n 1 "${DATA_DIR}/.oneinstack-managed")" == "oneinstack-data-v1" ]] ||
  { printf '[backup] Error: managed data marker is missing or invalid.\n' >&2; exit 1; }
BACKUP_ROOT="${DATA_DIR}/backups"
LOCK_DIR="${BACKUP_ROOT}/.backup.lock"
LOCK_ACQUIRED=0
PARTIAL_DIR=""

fail() {
  printf '[backup] Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local exit_code=$?

  [[ -z "${PARTIAL_DIR}" || ! -d "${PARTIAL_DIR}" ]] ||
    rm -rf -- "${PARTIAL_DIR}"
  if ((LOCK_ACQUIRED == 1)); then
    rmdir "${LOCK_DIR}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}

trap cleanup EXIT

sha256_digest() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required."
  fi
}

acquire_backup_lock() {
  mkdir -p "${BACKUP_ROOT}"
  mkdir "${LOCK_DIR}" 2>/dev/null ||
    fail "Another backup is already running: ${LOCK_DIR}"
  LOCK_ACQUIRED=1
}

encrypt_backup_payloads() {
  local destination="$1"
  local recipient="$2"
  local file

  [[ -n "${recipient}" ]] || return 0
  command -v age >/dev/null 2>&1 ||
    fail "age is required when BACKUP_AGE_RECIPIENT is configured."

  while IFS= read -r file; do
    age --encrypt --recipient "${recipient}" \
      --output "${file}.age" "${file}"
    rm -f -- "${file}"
  done < <(
    find "${destination}" -mindepth 1 -maxdepth 1 -type f \
      ! -name manifest.env -print | sort
  )
}

write_checksums() {
  local destination="$1"
  local file
  local basename

  : >"${destination}/SHA256SUMS"
  while IFS= read -r file; do
    basename="${file##*/}"
    printf '%s  %s\n' "$(sha256_digest "${file}")" "${basename}" \
      >>"${destination}/SHA256SUMS"
  done < <(
    find "${destination}" -mindepth 1 -maxdepth 1 -type f \
      ! -name SHA256SUMS -print | sort
  )
}

verify_backup_file() {
  local file="$1"
  local checksum_file
  local expected
  local actual
  local basename

  checksum_file="${file%/*}/SHA256SUMS"
  if [[ ! -f "${checksum_file}" ]]; then
    printf '[backup] Warning: no SHA256SUMS found; treating this as a legacy backup.\n' >&2
    return 0
  fi

  basename="${file##*/}"
  expected="$(awk -v name="${basename}" '$2 == name { print $1; exit }' "${checksum_file}")"
  [[ -n "${expected}" ]] ||
    fail "No checksum entry exists for ${basename}."
  actual="$(sha256_digest "${file}")"
  [[ "${actual}" == "${expected}" ]] ||
    fail "Checksum verification failed for ${file}."
}

validate_backup_manifest() {
  local file="$1"
  local expected_engine="${2:-}"
  local manifest
  local status
  local backup_engine

  manifest="${file%/*}/manifest.env"
  if [[ ! -f "${manifest}" ]]; then
    printf '[backup] Warning: no manifest.env found; treating this as a legacy backup.\n' >&2
    return 0
  fi

  verify_backup_file "${manifest}"
  status="$(env_get "${manifest}" STATUS)"
  [[ "${status}" == "complete" ]] ||
    fail "Backup manifest is not complete: ${manifest}"
  if [[ -n "${expected_engine}" ]]; then
    backup_engine="$(env_get "${manifest}" DATABASE_ENGINE)"
    [[ -n "${backup_engine}" ]] ||
      fail "Backup manifest does not declare DATABASE_ENGINE."
    [[ "${backup_engine}" == "${expected_engine}" ]] ||
      fail "Backup engine ${backup_engine} does not match the selected ${expected_engine} database."
  fi
}

stream_backup_file() {
  local file="$1"
  local identity_file

  if [[ "${file}" == *.age ]]; then
    command -v age >/dev/null 2>&1 ||
      fail "age is required to restore encrypted backups."
    identity_file="$(env_get "${ENV_FILE}" BACKUP_AGE_IDENTITY_FILE)"
    [[ -n "${identity_file}" && -r "${identity_file}" ]] ||
      fail "BACKUP_AGE_IDENTITY_FILE must point to a readable age identity."
    age --decrypt --identity "${identity_file}" "${file}"
  else
    cat "${file}"
  fi
}

validate_archive_members() {
  local file="$1"
  local allowed_roots="${2:-}"

  stream_backup_file "${file}" |
    tar -tzf - |
    awk -v roots="${allowed_roots}" '
      BEGIN {
        count = split(roots, allowed, ",")
      }
      {
        name = $0
        sub(/^\.\//, "", name)
        if (name ~ /^\// || name ~ /(^|\/)\.\.(\/|$)/) exit 2
        if (roots == "") next
        valid = 0
        for (i = 1; i <= count; i++) {
          if (name == allowed[i] || index(name, allowed[i] "/") == 1) {
            valid = 1
            break
          }
        }
        if (!valid) exit 3
      }
    ' ||
    fail "Backup archive contains an unsafe or unexpected path: ${file}"
}

create_database_backup() {
  local engine="$1"
  local destination="$2"

  case "${engine}" in
    mysql | percona)
      "${MANAGER[@]}" compose exec -T "${engine}" sh -c \
        'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" exec mysqldump -uroot --all-databases --single-transaction --routines --events' |
        gzip -c >"${destination}/database-${engine}.sql.gz"
      ;;
    mariadb)
      "${MANAGER[@]}" compose exec -T mariadb sh -c \
        'MARIADB_PWD="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" exec mariadb-dump -uroot --all-databases --single-transaction --routines --events' |
        gzip -c >"${destination}/database-mariadb.sql.gz"
      ;;
    postgresql)
      "${MANAGER[@]}" compose exec -T postgresql sh -c \
        'exec pg_dumpall -U "$POSTGRES_USER"' |
        gzip -c >"${destination}/database-postgresql.sql.gz"
      ;;
    mongodb)
      "${MANAGER[@]}" compose exec -T mongodb sh -c \
        'exec mongodump --archive --gzip --username "$MONGO_INITDB_ROOT_USERNAME" --password "$(cat "$MONGO_INITDB_ROOT_PASSWORD_FILE")" --authenticationDatabase admin' \
        >"${destination}/database-mongodb.archive.gz"
      ;;
    none) ;;
    *) fail "Unsupported database engine: ${engine}" ;;
  esac
}

create_backup() {
  local timestamp
  local destination
  local engine
  local remote=""
  local retention_days
  local encryption_recipient
  local backup_name
  local suffix=0

  while (($# > 0)); do
    case "$1" in
      --remote) remote="${2:?--remote requires an rclone destination}"; shift 2 ;;
      *) fail "Unknown backup option: $1" ;;
    esac
  done

  timestamp="$(date +%Y%m%d-%H%M%S)"
  destination="${BACKUP_ROOT}/${timestamp}"
  while [[ -e "${destination}" ]]; do
    ((suffix += 1))
    destination="${BACKUP_ROOT}/${timestamp}-${suffix}"
  done
  backup_name="${destination##*/}"
  engine="$(env_get "${ENV_FILE}" DATABASE_ENGINE mysql)"
  encryption_recipient="$(env_get "${ENV_FILE}" BACKUP_AGE_RECIPIENT)"

  acquire_backup_lock
  PARTIAL_DIR="$(mktemp -d "${BACKUP_ROOT}/.${timestamp}.partial.XXXXXX")"

  tar -czf "${PARTIAL_DIR}/webroot.tar.gz" -C "${DATA_DIR}/www" .
  tar -czf "${PARTIAL_DIR}/configuration.tar.gz" \
    -C "${DATA_DIR}" config sites
  tar -czf "${PARTIAL_DIR}/tomcat-webapps.tar.gz" \
    -C "${DATA_DIR}" tomcat/webapps
  tar -czf "${PARTIAL_DIR}/ftp-state.tar.gz" \
    -C "${DATA_DIR}" ftp
  create_database_backup "${engine}" "${PARTIAL_DIR}"

  {
    printf 'CREATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'DATABASE_ENGINE=%s\n' "${engine}"
    printf 'COMPOSE_PROJECT_NAME=%s\n' "$(env_get "${ENV_FILE}" COMPOSE_PROJECT_NAME oneinstack)"
    printf 'ENCRYPTED=%s\n' "$([[ -n "${encryption_recipient}" ]] && printf 1 || printf 0)"
    printf 'STATUS=complete\n'
  } >"${PARTIAL_DIR}/manifest.env"

  encrypt_backup_payloads "${PARTIAL_DIR}" "${encryption_recipient}"
  write_checksums "${PARTIAL_DIR}"
  mv "${PARTIAL_DIR}" "${destination}"
  PARTIAL_DIR=""

  if [[ -n "${remote}" ]]; then
    command -v rclone >/dev/null 2>&1 ||
      fail "rclone is required for --remote backups."
    rclone copy "${destination}" "${remote%/}/${backup_name}"
  fi

  retention_days="$(env_get "${ENV_FILE}" BACKUP_RETENTION_DAYS 180)"
  [[ "${retention_days}" =~ ^[0-9]+$ ]] ||
    fail "BACKUP_RETENTION_DAYS must be a non-negative integer."
  find "${BACKUP_ROOT}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -name '[0-9]*' \
    -mtime "+${retention_days}" \
    -exec rm -rf -- {} +

  printf '[backup] Created %s\n' "${destination}"
}

restore_database() {
  local file="${1:-}"
  local confirmation="${2:-}"
  local engine

  [[ -f "${file}" ]] || fail "Backup file not found: ${file}"
  [[ "${confirmation}" == "--yes" ]] ||
    fail "Database restore changes persistent data. Repeat with --yes."
  engine="$(env_get "${ENV_FILE}" DATABASE_ENGINE mysql)"
  verify_backup_file "${file}"
  validate_backup_manifest "${file}" "${engine}"

  case "${engine}" in
    mysql | percona)
      stream_backup_file "${file}" | gzip -dc |
        "${MANAGER[@]}" compose exec -T "${engine}" sh -c \
          'MYSQL_PWD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")" exec mysql -uroot'
      ;;
    mariadb)
      stream_backup_file "${file}" | gzip -dc |
        "${MANAGER[@]}" compose exec -T mariadb sh -c \
          'MARIADB_PWD="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" exec mariadb -uroot'
      ;;
    postgresql)
      stream_backup_file "${file}" | gzip -dc |
        "${MANAGER[@]}" compose exec -T postgresql sh -c \
          'exec psql -U "$POSTGRES_USER" -d postgres'
      ;;
    mongodb)
      stream_backup_file "${file}" |
      "${MANAGER[@]}" compose exec -T mongodb sh -c \
        'exec mongorestore --archive --gzip --drop --username "$MONGO_INITDB_ROOT_USERNAME" --password "$(cat "$MONGO_INITDB_ROOT_PASSWORD_FILE")" --authenticationDatabase admin'
      ;;
    *) fail "Database restore is not available for ${engine}." ;;
  esac
}

restore_web() {
  local file="${1:-}"
  local confirmation="${2:-}"

  [[ -f "${file}" ]] || fail "Backup file not found: ${file}"
  [[ "${confirmation}" == "--yes" ]] ||
    fail "Web restore overwrites matching files. Repeat with --yes."
  verify_backup_file "${file}"
  validate_backup_manifest "${file}"
  validate_archive_members "${file}"
  stream_backup_file "${file}" | tar -xzf - -C "${DATA_DIR}/www"
  printf '[backup] Restored web files from %s\n' "${file}"
}

restore_managed_archive() {
  local file="${1:-}"
  local confirmation="${2:-}"
  local label="$3"
  local allowed_roots="$4"

  [[ -f "${file}" ]] || fail "Backup file not found: ${file}"
  [[ "${confirmation}" == "--yes" ]] ||
    fail "${label} restore overwrites matching files. Repeat with --yes."
  verify_backup_file "${file}"
  validate_backup_manifest "${file}"
  validate_archive_members "${file}" "${allowed_roots}"
  stream_backup_file "${file}" | tar -xzf - -C "${DATA_DIR}"
  printf '[backup] Restored %s from %s\n' "${label}" "${file}"
}

command="${1:-create}"
if (($# > 0)); then shift; fi

case "${command}" in
  create) create_backup "$@" ;;
  restore-db) restore_database "$@" ;;
  restore-web) restore_web "$@" ;;
  restore-config)
    restore_managed_archive "${1:-}" "${2:-}" configuration "config,sites"
    "${SCRIPT_DIR}/scripts/site.sh" "${ENV_FILE}" render-all
    ;;
  restore-tomcat)
    restore_managed_archive "${1:-}" "${2:-}" "Tomcat webapps" "tomcat"
    ;;
  restore-ftp)
    restore_managed_archive "${1:-}" "${2:-}" "FTP state" "ftp"
    ;;
  *) fail "Unknown backup command: ${command}" ;;
esac
