#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:?environment file is required}"
shift

# shellcheck source=env.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/env.sh"

DATA_DIR="$(env_get "${ENV_FILE}" ONEINSTACK_DATA_DIR)"
[[ -n "${DATA_DIR}" && "${DATA_DIR}" == /* ]] ||
  { printf '[site] Error: ONEINSTACK_DATA_DIR must be an absolute path.\n' >&2; exit 1; }
DATA_DIR="${DATA_DIR%/}"
if [[ ! -f "${DATA_DIR}/.oneinstack-managed" ]] ||
  [[ "$(head -n 1 "${DATA_DIR}/.oneinstack-managed")" != "oneinstack-data-v1" ]]; then
  printf '[site] Error: managed data marker is missing or invalid.\n' >&2
  exit 1
fi
METADATA_DIR="${DATA_DIR}/sites"

fail() {
  printf '[site] Error: %s\n' "$*" >&2
  exit 1
}

validate_domain() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$|^[A-Za-z0-9]$ ]] ||
    fail "Invalid domain: $1"
  [[ "$1" != *..* ]] || fail "Invalid domain: $1"
}

validate_root() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
    fail "Site root must be a relative path using letters, numbers, '.', '_' or '-'."
  [[ "$1" != /* && "$1" != *..* ]] || fail "Site root cannot escape the managed www directory."
}

validate_target() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+:[0-9]{1,5}$ ]] ||
    fail "Proxy target must use HOST:PORT."
}

metadata_file() {
  printf '%s/%s.env\n' "${METADATA_DIR}" "$1"
}

read_site() {
  local domain="$1"
  local file
  file="$(metadata_file "${domain}")"
  [[ -f "${file}" ]] || fail "Site does not exist: ${domain}"

  SITE_DOMAIN="$(env_get "${file}" DOMAIN)"
  SITE_ROOT="$(env_get "${file}" ROOT)"
  SITE_RUNTIME="$(env_get "${file}" RUNTIME)"
  SITE_TARGET="$(env_get "${file}" TARGET)"
  SITE_TLS="$(env_get "${file}" TLS auto)"
}

nginx_runtime_block() {
  case "${SITE_RUNTIME}" in
    php | php82 | php83 | php84 | php85)
      cat <<EOF
  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php$ {
    try_files \$fastcgi_script_name =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_pass ${SITE_TARGET};
  }
EOF
      ;;
    static)
      cat <<'EOF'
  location / {
    try_files $uri $uri/ =404;
  }
EOF
      ;;
    proxy | node | tomcat)
      cat <<EOF
  location / {
    proxy_pass http://${SITE_TARGET};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
EOF
      ;;
  esac
}

render_nginx_family() {
  local engine="$1"
  local output_dir
  local output_file
  local temporary_file
  local certificate_dir="${DATA_DIR}/certs/live/${SITE_DOMAIN}"

  case "${engine}" in
    nginx) output_dir="${DATA_DIR}/config/nginx" ;;
    tengine) output_dir="${DATA_DIR}/config/tengine" ;;
    openresty) output_dir="${DATA_DIR}/config/openresty" ;;
    *) fail "Unsupported Nginx-family engine: ${engine}" ;;
  esac

  output_file="${output_dir}/${SITE_DOMAIN}.conf"
  temporary_file="$(mktemp "${output_dir}/.${SITE_DOMAIN}.XXXXXX")"

  {
    printf 'server {\n'
    printf '  listen 80;\n'
    printf '  listen [::]:80;\n'
    if [[ "${SITE_TLS}" != "off" && -f "${certificate_dir}/fullchain.pem" && -f "${certificate_dir}/privkey.pem" ]]; then
      printf '  listen 443 ssl;\n'
      printf '  listen [::]:443 ssl;\n'
      printf '  ssl_certificate /etc/letsencrypt/live/%s/fullchain.pem;\n' "${SITE_DOMAIN}"
      printf '  ssl_certificate_key /etc/letsencrypt/live/%s/privkey.pem;\n' "${SITE_DOMAIN}"
      printf '  ssl_protocols TLSv1.2 TLSv1.3;\n'
    fi
    printf '  server_name %s;\n' "${SITE_DOMAIN}"
    printf '  root /var/www/html/%s;\n' "${SITE_ROOT}"
    printf '  index index.php index.html;\n\n'
    cat <<'EOF'
  location ^~ /.well-known/acme-challenge/ {
    root /var/www/acme;
  }

EOF
    nginx_runtime_block
    cat <<'EOF'

  location ~ /\.(?!well-known).* {
    deny all;
  }
}
EOF
  } >"${temporary_file}"

  mv "${temporary_file}" "${output_file}"
}

apache_runtime_block() {
  case "${SITE_RUNTIME}" in
    php | php82 | php83 | php84 | php85)
      cat <<EOF
  <FilesMatch "\.php$">
    SetHandler "proxy:fcgi://${SITE_TARGET}"
  </FilesMatch>
EOF
      ;;
    static)
      ;;
    proxy | node | tomcat)
      cat <<EOF
  ProxyPreserveHost On
  ProxyPass / http://${SITE_TARGET}/
  ProxyPassReverse / http://${SITE_TARGET}/
EOF
      ;;
  esac
}

render_apache() {
  local output_file="${DATA_DIR}/config/apache/${SITE_DOMAIN}.conf"
  local temporary_file
  local certificate_dir="${DATA_DIR}/certs/live/${SITE_DOMAIN}"

  temporary_file="$(mktemp "${DATA_DIR}/config/apache/.${SITE_DOMAIN}.XXXXXX")"
  {
    printf '<VirtualHost *:80>\n'
    printf '  ServerName %s\n' "${SITE_DOMAIN}"
    printf '  DocumentRoot "/var/www/html/%s"\n' "${SITE_ROOT}"
    printf '  DirectoryIndex index.php index.html\n'
    printf '  Alias /.well-known/acme-challenge/ "/var/www/acme/.well-known/acme-challenge/"\n'
    printf '  <Directory "/var/www/html/%s">\n' "${SITE_ROOT}"
    printf '    AllowOverride All\n'
    printf '    Require all granted\n'
    printf '  </Directory>\n'
    apache_runtime_block
    printf '</VirtualHost>\n'

    if [[ "${SITE_TLS}" != "off" && -f "${certificate_dir}/fullchain.pem" && -f "${certificate_dir}/privkey.pem" ]]; then
      printf '\n<VirtualHost *:443>\n'
      printf '  ServerName %s\n' "${SITE_DOMAIN}"
      printf '  DocumentRoot "/var/www/html/%s"\n' "${SITE_ROOT}"
      printf '  SSLEngine on\n'
      printf '  SSLCertificateFile "/etc/letsencrypt/live/%s/fullchain.pem"\n' "${SITE_DOMAIN}"
      printf '  SSLCertificateKeyFile "/etc/letsencrypt/live/%s/privkey.pem"\n' "${SITE_DOMAIN}"
      printf '  <Directory "/var/www/html/%s">\n' "${SITE_ROOT}"
      printf '    AllowOverride All\n'
      printf '    Require all granted\n'
      printf '  </Directory>\n'
      apache_runtime_block
      printf '</VirtualHost>\n'
    fi
  } >"${temporary_file}"
  mv "${temporary_file}" "${output_file}"
}

caddy_runtime_block() {
  case "${SITE_RUNTIME}" in
    php | php82 | php83 | php84 | php85)
      cat <<EOF
  php_fastcgi ${SITE_TARGET}
  file_server
EOF
      ;;
    static)
      printf '  file_server\n'
      ;;
    proxy | node | tomcat)
      printf '  reverse_proxy %s\n' "${SITE_TARGET}"
      ;;
  esac
}

render_caddy() {
  local output_file="${DATA_DIR}/config/caddy/sites/${SITE_DOMAIN}.caddy"
  local temporary_file
  local address="${SITE_DOMAIN}"

  [[ "${SITE_TLS}" != "off" ]] || address="http://${SITE_DOMAIN}"
  temporary_file="$(mktemp "${DATA_DIR}/config/caddy/sites/.${SITE_DOMAIN}.XXXXXX")"
  {
    printf '%s {\n' "${address}"
    printf '  root * /var/www/html/%s\n' "${SITE_ROOT}"
    caddy_runtime_block
    printf '}\n'
  } >"${temporary_file}"
  mv "${temporary_file}" "${output_file}"
}

render_site() {
  local domain="$1"
  local engine

  read_site "${domain}"
  engine="$(env_get "${ENV_FILE}" WEB_ENGINE nginx)"

  case "${engine}" in
    nginx | tengine | openresty) render_nginx_family "${engine}" ;;
    apache) render_apache ;;
    caddy) render_caddy ;;
    *) fail "Unsupported WEB_ENGINE: ${engine}" ;;
  esac

  printf '[site] Rendered %s for %s\n' "${domain}" "${engine}"
}

add_site() {
  local domain="${1:-}"
  local root
  local runtime="php"
  local target=""
  local tls="auto"
  local file
  local temporary_file

  [[ -n "${domain}" ]] || fail "Usage: site add DOMAIN [options]"
  shift
  validate_domain "${domain}"
  root="${domain}"

  while (($# > 0)); do
    case "$1" in
      --root) root="${2:?--root requires a path}"; shift 2 ;;
      --runtime) runtime="${2:?--runtime requires a value}"; shift 2 ;;
      --target) target="${2:?--target requires HOST:PORT}"; shift 2 ;;
      --tls) tls="${2:?--tls requires auto or off}"; shift 2 ;;
      *) fail "Unknown site option: $1" ;;
    esac
  done

  validate_root "${root}"
  [[ "${runtime}" =~ ^(php|php82|php83|php84|php85|static|proxy|node|tomcat)$ ]] ||
    fail "Runtime must be php, php82-php85, static, proxy, node or tomcat."
  [[ "${tls}" =~ ^(auto|off)$ ]] || fail "TLS mode must be auto or off."

  case "${runtime}" in
    php) target="${target:-php:9000}" ;;
    php82 | php83 | php84 | php85) target="${target:-${runtime}:9000}" ;;
    node) target="${target:-node:3000}" ;;
    tomcat) target="${target:-tomcat:8080}" ;;
    proxy) [[ -n "${target}" ]] || fail "--target is required for proxy sites." ;;
  esac
  [[ -z "${target}" ]] || validate_target "${target}"

  mkdir -p "${METADATA_DIR}" "${DATA_DIR}/www/${root}"
  file="$(metadata_file "${domain}")"
  temporary_file="$(mktemp "${METADATA_DIR}/.${domain}.XXXXXX")"
  {
    printf 'DOMAIN=%s\n' "${domain}"
    printf 'ROOT=%s\n' "${root}"
    printf 'RUNTIME=%s\n' "${runtime}"
    printf 'TARGET=%s\n' "${target}"
    printf 'TLS=%s\n' "${tls}"
  } >"${temporary_file}"
  chmod 0600 "${temporary_file}"
  mv "${temporary_file}" "${file}"

  if [[ ! -e "${DATA_DIR}/www/${root}/index.html" && ! -e "${DATA_DIR}/www/${root}/index.php" ]]; then
    printf 'OneinStack site %s is ready.\n' "${domain}" >"${DATA_DIR}/www/${root}/index.html"
  fi

  render_site "${domain}"
}

delete_site() {
  local domain="${1:-}"
  local purge=0
  local root

  [[ -n "${domain}" ]] || fail "Usage: site delete DOMAIN [--purge]"
  shift
  validate_domain "${domain}"
  read_site "${domain}"
  root="${SITE_ROOT}"

  if [[ "${1:-}" == "--purge" ]]; then
    purge=1
    shift
  fi
  (($# == 0)) || fail "Unknown site delete option: $1"

  rm -f \
    "${DATA_DIR}/config/nginx/${domain}.conf" \
    "${DATA_DIR}/config/tengine/${domain}.conf" \
    "${DATA_DIR}/config/openresty/${domain}.conf" \
    "${DATA_DIR}/config/apache/${domain}.conf" \
    "${DATA_DIR}/config/caddy/sites/${domain}.caddy" \
    "$(metadata_file "${domain}")"

  if ((purge == 1)); then
    validate_root "${root}"
    rm -rf -- "${DATA_DIR}/www/${root}"
    printf '[site] Deleted %s and its site files.\n' "${domain}"
  else
    printf '[site] Deleted %s configuration; site files were preserved.\n' "${domain}"
  fi
}

list_sites() {
  local file
  local found=0

  printf '%-32s %-10s %-24s %s\n' "DOMAIN" "RUNTIME" "TARGET" "ROOT"
  for file in "${METADATA_DIR}"/*.env; do
    [[ -f "${file}" ]] || continue
    found=1
    printf '%-32s %-10s %-24s %s\n' \
      "$(env_get "${file}" DOMAIN)" \
      "$(env_get "${file}" RUNTIME)" \
      "$(env_get "${file}" TARGET -)" \
      "$(env_get "${file}" ROOT)"
  done
  ((found == 1)) || printf '%s\n' "(no sites)"
}

render_all() {
  local file
  for file in "${METADATA_DIR}"/*.env; do
    [[ -f "${file}" ]] || continue
    render_site "$(env_get "${file}" DOMAIN)"
  done
}

command="${1:-list}"
if (($# > 0)); then shift; fi

case "${command}" in
  add) add_site "$@" ;;
  delete | del) delete_site "$@" ;;
  list) list_sites ;;
  render) render_site "${1:?domain is required}" ;;
  render-all) render_all ;;
  *) fail "Unknown site command: ${command}" ;;
esac
