#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOT_ROOT="${BOT_ROOT:-/home/administrator/bot}"
if [[ -f "${BOT_ROOT}/.env.local" ]]; then
  set -a
  source "${BOT_ROOT}/.env.local"
  set +a
fi
if [[ -f "${ARMY_ROOT}/army.env" ]]; then
  set -a
  source "${ARMY_ROOT}/army.env"
  set +a
fi

RUNTIME_DIR="${RUNTIME_DIR:-${BOT_ROOT}/runtime}"
LOG_DIR="${LOG_DIR:-${RUNTIME_DIR}/logs}"
LOCK_DIR="${LOCK_DIR:-${RUNTIME_DIR}/locks}"
ARMY_STATE_DIR="${ARMY_STATE_DIR:-${RUNTIME_DIR}/army}"
ESCALATION_DIR="${ESCALATION_DIR:-${RUNTIME_DIR}/escalation}"
PENDING_FILE="${PENDING_FILE:-${ESCALATION_DIR}/pending_questions.md}"
REPORT_DIR="${REPORT_DIR:-${BOT_ROOT}/ops/reports}"
ADVISOR_DIR="${ADVISOR_DIR:-${REPORT_DIR}/advisor}"

WATCHDOG_LOG="${WATCHDOG_LOG:-${LOG_DIR}/watchdog.log}"
SCHEDULER_LOG="${SCHEDULER_LOG:-${LOG_DIR}/scheduler.log}"
OBSERVE_LOG="${OBSERVE_LOG:-${LOG_DIR}/observe.log}"
VERIFY_LOG="${VERIFY_LOG:-${LOG_DIR}/verify.log}"
ADVISOR_LOG="${ADVISOR_LOG:-${LOG_DIR}/codex-advisor.log}"
GATEWAY_SUPERVISED_LOG="${GATEWAY_SUPERVISED_LOG:-${LOG_DIR}/gateway-supervised.log}"

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
CODEX_BIN="${CODEX_BIN:-codex}"

ROUTER_BASE_URL="${ROUTER_BASE_URL:-https://test-router.yeying.pub/v1}"
ROUTER_MODEL="${ROUTER_MODEL:-gpt-5.3-codex}"

ARMY_ENABLE_CODEX="${ARMY_ENABLE_CODEX:-1}"
ARMY_ENABLE_SWARM="${ARMY_ENABLE_SWARM:-0}"
ARMY_OBSERVE_INTERVAL_MIN="${ARMY_OBSERVE_INTERVAL_MIN:-15}"
ARMY_VERIFY_INTERVAL_MIN="${ARMY_VERIFY_INTERVAL_MIN:-30}"
ARMY_ADVISOR_INTERVAL_MIN="${ARMY_ADVISOR_INTERVAL_MIN:-60}"
ARMY_SWARM_INTERVAL_MIN="${ARMY_SWARM_INTERVAL_MIN:-360}"
ARMY_CODEX_TIMEOUT_SEC="${ARMY_CODEX_TIMEOUT_SEC:-420}"
ARMY_CODEX_SANDBOX="${ARMY_CODEX_SANDBOX:-read-only}"

mkdir -p "${LOG_DIR}" "${LOCK_DIR}" "${ARMY_STATE_DIR}" "${ESCALATION_DIR}" "${REPORT_DIR}" "${ADVISOR_DIR}"
touch "${PENDING_FILE}" "${WATCHDOG_LOG}" "${SCHEDULER_LOG}" "${OBSERVE_LOG}" "${VERIFY_LOG}" "${ADVISOR_LOG}" "${GATEWAY_SUPERVISED_LOG}"

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" || -z "${ROUTER_API_KEY:-}" ]]; then
  eval "$(python3 - <<'PY' 2>/dev/null
import json
from pathlib import Path
p = Path('/home/administrator/.openclaw/openclaw.json')
out = {'token':'', 'apiKey':''}
if p.exists():
    try:
        obj = json.loads(p.read_text())
        out['token'] = obj.get('gateway',{}).get('auth',{}).get('token','') or ''
        out['apiKey'] = obj.get('models',{}).get('providers',{}).get('router',{}).get('apiKey','') or ''
    except Exception:
        pass
print(f"OPENCLAW_GATEWAY_TOKEN='{out['token'].replace("'", "'\\''")}'")
print(f"ROUTER_API_KEY='{out['apiKey'].replace("'", "'\\''")}'")
PY
)"
fi

export OPENCLAW_GATEWAY_TOKEN ROUTER_API_KEY

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
slot_now() { date '+%Y%m%d%H%M'; }

log_watchdog() { printf '[%s] %s\n' "$(timestamp)" "$*" | tee -a "${WATCHDOG_LOG}"; }
log_scheduler() { printf '[%s] %s\n' "$(timestamp)" "$*" | tee -a "${SCHEDULER_LOG}"; }

append_pending() {
  local source="${1:-watchdog}"
  local problem="${2:-unknown}"
  local action="${3:-manual_check}"
  {
    printf -- '- [%s] source=%s\n' "$(timestamp)" "${source}"
    printf -- '  - problem: %s\n' "${problem}"
    printf -- '  - action: %s\n' "${action}"
  } >> "${PENDING_FILE}"
}

gateway_is_running() {
  pgrep -f 'openclaw-gateway|openclaw gateway run' >/dev/null 2>&1
}

gateway_pids() {
  pgrep -fa 'openclaw-gateway|openclaw gateway run' || true
}

start_gateway() {
  if gateway_is_running; then
    return 0
  fi
  nohup "${OPENCLAW_BIN}" gateway run --allow-unconfigured >>"${GATEWAY_SUPERVISED_LOG}" 2>&1 &
  echo $! > "${ARMY_STATE_DIR}/gateway.pid"
  sleep 4
}

stop_gateway() {
  pkill -f 'openclaw-gateway|openclaw gateway run' || true
  sleep 2
}

gateway_health() {
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    "${OPENCLAW_BIN}" gateway --token "${OPENCLAW_GATEWAY_TOKEN}" health 2>&1 || true
  else
    ss -ltnp | grep ':18789' || true
  fi
}

channel_status() {
  "${OPENCLAW_BIN}" channels status 2>&1 || true
}

channel_is_connected() {
  local status_text="${1:-}"
  grep -Eiq 'linked.*running.*connected|running.*connected.*linked|connected.*linked.*running' <<<"${status_text}"
}

router_health() {
  if [[ -z "${ROUTER_API_KEY:-}" ]]; then
    echo "ROUTER_API_KEY not set"
    return 0
  fi
  curl -fsS "${ROUTER_BASE_URL}/models" -H "Authorization: Bearer ${ROUTER_API_KEY}" | head -c 1000
}

safe_tail() {
  local file="$1"
  local lines="${2:-60}"
  if [[ -f "${file}" ]]; then
    tail -n "${lines}" "${file}"
  else
    echo "<missing: ${file}>"
  fi
}

run_with_timeout() {
  local timeout_sec="$1"; shift
  timeout "${timeout_sec}" "$@"
}
