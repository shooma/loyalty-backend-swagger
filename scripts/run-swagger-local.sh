#!/usr/bin/env bash

set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

printf 'Serving Swagger UI from %s\n' "${REPO_ROOT}"
printf 'Open http://%s:%s\n' "${HOST}" "${PORT}"

exec python3 -m http.server --bind "${HOST}" "${PORT}"
