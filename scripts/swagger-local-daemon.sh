#!/usr/bin/env bash

set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PID_FILE="${REPO_ROOT}/.swagger-local.pid"
LOG_FILE="${REPO_ROOT}/.swagger-local.log"

is_running() {
  if [[ ! -f "${PID_FILE}" ]]; then
    return 1
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi

  return 1
}

start_server() {
  if is_running; then
    printf 'Swagger server already running (PID %s)\n' "$(cat "${PID_FILE}")"
    printf 'Open http://%s:%s\n' "${HOST}" "${PORT}"
    return 0
  fi

  rm -f "${PID_FILE}"

  cd "${REPO_ROOT}"
  nohup python3 -m http.server --bind "${HOST}" "${PORT}" >"${LOG_FILE}" 2>&1 &
  local pid=$!
  echo "${pid}" > "${PID_FILE}"

  sleep 0.2
  if is_running; then
    printf 'Swagger server started in background (PID %s)\n' "${pid}"
    printf 'Open http://%s:%s\n' "${HOST}" "${PORT}"
    printf 'Logs: %s\n' "${LOG_FILE}"
  else
    printf 'Failed to start Swagger server. Check logs: %s\n' "${LOG_FILE}" >&2
    exit 1
  fi
}

stop_server() {
  if ! is_running; then
    rm -f "${PID_FILE}"
    printf 'Swagger server is not running\n'
    return 0
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  kill "${pid}" 2>/dev/null || true

  for _ in {1..20}; do
    if ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${PID_FILE}"
      printf 'Swagger server stopped\n'
      return 0
    fi
    sleep 0.1
  done

  printf 'Process %s did not stop gracefully, sending SIGKILL\n' "${pid}"
  kill -9 "${pid}" 2>/dev/null || true
  rm -f "${PID_FILE}"
  printf 'Swagger server stopped\n'
}

status_server() {
  if is_running; then
    printf 'Swagger server is running (PID %s)\n' "$(cat "${PID_FILE}")"
    printf 'URL: http://%s:%s\n' "${HOST}" "${PORT}"
    printf 'Logs: %s\n' "${LOG_FILE}"
  else
    printf 'Swagger server is not running\n'
    return 1
  fi
}

logs_server() {
  touch "${LOG_FILE}"
  tail -n 100 -f "${LOG_FILE}"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/swagger-local-daemon.sh <start|stop|status|restart|logs>
EOF
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    start)
      start_server
      ;;
    stop)
      stop_server
      ;;
    status)
      status_server
      ;;
    restart)
      stop_server
      start_server
      ;;
    logs)
      logs_server
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
