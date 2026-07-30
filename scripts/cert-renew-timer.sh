#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-}"
MANAGER="${2:-}"
ENV_FILE="${3:-}"

fail() {
  printf '[cert-renew] Error: %s\n' "$*" >&2
  exit 1
}

[[ -n "${MANAGER}" && "${MANAGER}" == /* && -x "${MANAGER}" ]] ||
  fail "The manager must be an executable absolute path."
[[ -n "${ENV_FILE}" && "${ENV_FILE}" == /* && -f "${ENV_FILE}" ]] ||
  fail "The environment file must be an existing absolute path."

# shellcheck source=env.sh
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"

PROJECT_NAME="$(env_get "${ENV_FILE}" COMPOSE_PROJECT_NAME oneinstack)"
[[ "${PROJECT_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
  fail "COMPOSE_PROJECT_NAME is not safe for a systemd unit name."
UNIT_PREFIX="oneinstack-${PROJECT_NAME}-cert-renew"
SERVICE_UNIT="${UNIT_PREFIX}.service"
TIMER_UNIT="${UNIT_PREFIX}.timer"
SYSTEMD_DIR="/etc/systemd/system"

systemd_quote() {
  local value="$1"

  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] ||
    fail "Systemd paths must not contain line breaks."
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "${value}"
}

render_service() {
  cat <<EOF
[Unit]
Description=Renew OneinStack certificates for ${PROJECT_NAME}
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=$(systemd_quote "${MANAGER}") --env-file $(systemd_quote "${ENV_FILE}") tls renew
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
}

render_timer() {
  cat <<EOF
[Unit]
Description=Run ${SERVICE_UNIT} twice daily

[Timer]
OnCalendar=*-*-* 03:17:00
OnCalendar=*-*-* 15:17:00
RandomizedDelaySec=45m
Persistent=true
Unit=${SERVICE_UNIT}

[Install]
WantedBy=timers.target
EOF
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 ||
    fail "systemctl is required."
  [[ -d "${SYSTEMD_DIR}" ]] ||
    fail "${SYSTEMD_DIR} does not exist."
}

case "${ACTION}" in
  render)
    printf '%s\n' "### ${SERVICE_UNIT}"
    render_service
    printf '%s\n' "### ${TIMER_UNIT}"
    render_timer
    ;;
  install)
    require_systemd
    ((EUID == 0)) ||
      fail "timer-install must run as root."
    render_service >"${SYSTEMD_DIR}/${SERVICE_UNIT}"
    render_timer >"${SYSTEMD_DIR}/${TIMER_UNIT}"
    chmod 0644 \
      "${SYSTEMD_DIR}/${SERVICE_UNIT}" \
      "${SYSTEMD_DIR}/${TIMER_UNIT}"
    systemctl daemon-reload
    systemctl enable --now "${TIMER_UNIT}"
    printf '[cert-renew] Installed and started %s\n' "${TIMER_UNIT}"
    ;;
  status)
    require_systemd
    systemctl status "${TIMER_UNIT}" --no-pager
    systemctl list-timers "${TIMER_UNIT}" --no-pager
    ;;
  remove)
    require_systemd
    ((EUID == 0)) ||
      fail "timer-remove must run as root."
    systemctl disable --now "${TIMER_UNIT}" 2>/dev/null || true
    rm -f -- \
      "${SYSTEMD_DIR}/${TIMER_UNIT}" \
      "${SYSTEMD_DIR}/${SERVICE_UNIT}"
    systemctl daemon-reload
    printf '[cert-renew] Removed %s\n' "${TIMER_UNIT}"
    ;;
  *)
    fail "Usage: cert-renew-timer.sh {render|install|status|remove} MANAGER ENV_FILE"
    ;;
esac
