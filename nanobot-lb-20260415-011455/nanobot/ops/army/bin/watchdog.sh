#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

if ! command -v "${OPENCLAW_BIN}" >/dev/null 2>&1; then
  log_watchdog "openclaw missing"
  append_pending "watchdog" "openclaw_missing" "install_openclaw_and_reconfigure"
  exit 1
fi

if ! gateway_is_running; then
  log_watchdog "gateway down -> starting"
  start_gateway || true
fi

status_text="$(channel_status)"
if grep -qi 'Gateway not reachable' <<<"${status_text}"; then
  log_watchdog "gateway unreachable from cli -> restart once"
  stop_gateway || true
  start_gateway || true
  status_text="$(channel_status)"
fi

if channel_is_connected "${status_text}"; then
  log_watchdog "whatsapp channel healthy"
else
  log_watchdog "whatsapp channel degraded"
  append_pending "watchdog" "whatsapp_not_fully_connected" "check_login_and_network"
fi

health_text="$(gateway_health)"
if grep -Eiq 'OK|healthy|status.*ok|"ok"' <<<"${health_text}"; then
  log_watchdog "gateway health ok"
else
  log_watchdog "gateway health uncertain"
  append_pending "watchdog" "gateway_health_uncertain" "inspect_gateway_log"
fi
