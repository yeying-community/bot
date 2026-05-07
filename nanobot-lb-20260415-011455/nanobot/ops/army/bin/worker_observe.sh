#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ts="$(date '+%Y%m%d-%H%M%S')"
report="${REPORT_DIR}/observe-${ts}.md"

status_text="$(channel_status)"
health_text="$(gateway_health)"
router_text="$(router_health 2>&1 || true)"

auto_gateway="$(gateway_pids)"

{
  echo "# Observe Report ${ts}"
  echo
  echo "- host: $(hostname)"
  echo "- user: $(whoami)"
  echo "- bot_root: ${BOT_ROOT}"
  echo "- openclaw: $(${OPENCLAW_BIN} --version 2>/dev/null || echo 'unknown')"
  echo "- node: $(node -v 2>/dev/null || echo 'unknown')"
  echo
  echo "## gateway_pids"
  echo '```text'
  printf '%s\n' "${auto_gateway:-<none>}"
  echo '```'
  echo
  echo "## channel_status"
  echo '```text'
  printf '%s\n' "${status_text}"
  echo '```'
  echo
  echo "## gateway_health"
  echo '```text'
  printf '%s\n' "${health_text}"
  echo '```'
  echo
  echo "## router_probe"
  echo '```text'
  printf '%s\n' "${router_text}"
  echo '```'
  echo
  echo "## tail: ${GATEWAY_SUPERVISED_LOG}"
  echo '```text'
  safe_tail "${GATEWAY_SUPERVISED_LOG}" 80
  echo '```'
  echo
  echo "## tail: ~/.openclaw/logs/gateway.log"
  echo '```text'
  safe_tail "/home/administrator/.openclaw/logs/gateway.log" 80
  echo '```'
} > "${report}"

cp "${report}" "${REPORT_DIR}/latest-observe.md"
printf '[%s] wrote %s\n' "$(timestamp)" "${report}" | tee -a "${OBSERVE_LOG}"
