#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

exec 8>"${LOCK_DIR}/guard.lock"
if ! flock -n 8; then
  echo "guard_loop already running"
  exit 0
fi

while true; do
  "${SCRIPT_DIR}/ensure_army.sh" || true
  sleep 300
done
