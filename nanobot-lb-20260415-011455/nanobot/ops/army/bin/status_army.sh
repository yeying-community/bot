#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=== army process ==="
pgrep -fa "${BOT_ROOT}/ops/army/bin/scheduler.sh" || echo "scheduler: not running"
pgrep -fa "${BOT_ROOT}/ops/army/bin/guard_loop.sh" || echo "guard_loop: not running"

echo
echo "=== gateway process ==="
gateway_pids || true

echo
echo "=== channel status ==="
channel_status || true

echo
echo "=== latest reports ==="
ls -lt "${REPORT_DIR}" | head -n 12 || true

echo
echo "=== pending escalation tail ==="
tail -n 40 "${PENDING_FILE}" || true

echo
echo "=== watchdog log tail ==="
tail -n 60 "${WATCHDOG_LOG}" || true

echo
echo "=== guard loop log tail ==="
tail -n 40 "${LOG_DIR}/guard-loop.log" 2>/dev/null || true

echo
echo "=== ensure log tail ==="
tail -n 40 "${LOG_DIR}/ensure-army.log" 2>/dev/null || true
