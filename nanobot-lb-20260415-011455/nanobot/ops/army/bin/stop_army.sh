#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

pkill -f "${BOT_ROOT}/ops/army/bin/scheduler.sh" || true
pkill -f "${BOT_ROOT}/ops/army/bin/guard_loop.sh" || true
rm -f "${ARMY_STATE_DIR}/scheduler.pid" "${ARMY_STATE_DIR}/guard.pid"
echo "scheduler+guard stopped"
