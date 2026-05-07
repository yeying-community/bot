#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

log_file="${LOG_DIR}/ensure-army.log"
exec >>"${log_file}" 2>&1
printf '[%s] ensure_army tick\n' "$(timestamp)"

if ! command -v "${OPENCLAW_BIN}" >/dev/null 2>&1; then
  printf '[%s] openclaw missing\n' "$(timestamp)"
  append_pending "ensure_army" "openclaw_missing" "install_openclaw"
  exit 1
fi

if ! gateway_is_running; then
  printf '[%s] gateway not running, start\n' "$(timestamp)"
  start_gateway || true
fi

if pgrep -f "${BOT_ROOT}/ops/army/bin/scheduler.sh" >/dev/null 2>&1; then
  printf '[%s] scheduler alive\n' "$(timestamp)"
else
  printf '[%s] scheduler down, starting\n' "$(timestamp)"
  nohup "${SCRIPT_DIR}/scheduler.sh" >>"${SCHEDULER_LOG}" 2>&1 &
  echo $! > "${ARMY_STATE_DIR}/scheduler.pid"
fi

status_text="$(channel_status)"
if channel_is_connected "${status_text}"; then
  printf '[%s] channel connected\n' "$(timestamp)"
else
  printf '[%s] channel degraded\n' "$(timestamp)"
  append_pending "ensure_army" "channel_degraded" "relink_or_check_network"
fi
