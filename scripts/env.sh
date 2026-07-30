#!/usr/bin/env bash

env_get() {
  local file="$1"
  local key="$2"
  local default_value="${3:-}"
  local value

  value="$(
    awk -v wanted="${key}" '
      index($0, wanted "=") == 1 {
        sub(/^[^=]*=/, "")
        print
        found = 1
        exit
      }
      END {
        if (!found) exit 1
      }
    ' "${file}" 2>/dev/null
  )" || value="${default_value}"
  printf '%s\n' "${value}"
}

env_set() {
  local file="$1"
  local key="$2"
  local value="$3"
  local directory
  local temporary_file

  [[ "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] ||
    { printf 'Invalid environment key: %s\n' "${key}" >&2; return 1; }
  [[ "${value}" != *$'\n'* ]] ||
    { printf 'Environment values cannot contain newlines.\n' >&2; return 1; }

  directory="$(dirname -- "${file}")"
  temporary_file="$(mktemp "${directory}/.oneinstack.env.XXXXXX")"

  awk -v wanted="${key}" -v replacement="${key}=${value}" '
    index($0, wanted "=") == 1 {
      if (!written) print replacement
      written = 1
      next
    }
    { print }
    END {
      if (!written) print replacement
    }
  ' "${file}" >"${temporary_file}"

  chmod 0600 "${temporary_file}"
  mv "${temporary_file}" "${file}"
}

csv_contains() {
  local csv="$1"
  local item="$2"
  case ",${csv}," in
    *,"${item}",*) return 0 ;;
    *) return 1 ;;
  esac
}

csv_add() {
  local csv="$1"
  local item="$2"

  if csv_contains "${csv}" "${item}"; then
    printf '%s\n' "${csv}"
  elif [[ -n "${csv}" ]]; then
    printf '%s,%s\n' "${csv}" "${item}"
  else
    printf '%s\n' "${item}"
  fi
}

csv_remove() {
  local csv="$1"
  local item="$2"
  local result=""
  local entry
  local old_ifs="${IFS}"

  IFS=','
  for entry in ${csv}; do
    if [[ -n "${entry}" && "${entry}" != "${item}" ]]; then
      result="$(csv_add "${result}" "${entry}")"
    fi
  done
  IFS="${old_ifs}"
  printf '%s\n' "${result}"
}
