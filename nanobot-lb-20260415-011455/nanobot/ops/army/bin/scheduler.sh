#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

exec 9>"${LOCK_DIR}/scheduler.lock"
if ! flock -n 9; then
  echo "scheduler already running"
  exit 0
fi

log_scheduler "scheduler started"

while true; do
  minute=$((10#$(date +%M)))
  hour_slot="$(date '+%Y%m%d%H')"
  minute_slot="$(date '+%Y%m%d%H%M')"

  "${SCRIPT_DIR}/watchdog.sh" || true

  if (( minute % ARMY_OBSERVE_INTERVAL_MIN == 0 )); then
    last_observe="$(cat "${ARMY_STATE_DIR}/last_observe.slot" 2>/dev/null || true)"
    if [[ "${minute_slot}" != "${last_observe}" ]]; then
      "${SCRIPT_DIR}/worker_observe.sh" || true
      echo "${minute_slot}" > "${ARMY_STATE_DIR}/last_observe.slot"
    fi
  fi

  if (( minute % ARMY_VERIFY_INTERVAL_MIN == 0 )); then
    last_verify="$(cat "${ARMY_STATE_DIR}/last_verify.slot" 2>/dev/null || true)"
    if [[ "${minute_slot}" != "${last_verify}" ]]; then
      "${SCRIPT_DIR}/worker_verify.sh" || true
      echo "${minute_slot}" > "${ARMY_STATE_DIR}/last_verify.slot"
    fi
  fi

  if (( minute % ARMY_ADVISOR_INTERVAL_MIN == 0 )); then
    last_adv="$(cat "${ARMY_STATE_DIR}/last_advisor.slot" 2>/dev/null || true)"
    if [[ "${hour_slot}-${minute}" != "${last_adv}" ]]; then
      "${SCRIPT_DIR}/worker_codex_advisor.sh" || true
      echo "${hour_slot}-${minute}" > "${ARMY_STATE_DIR}/last_advisor.slot"
    fi
  fi

  if (( minute % ARMY_SWARM_INTERVAL_MIN == 0 )); then
    last_swarm="$(cat "${ARMY_STATE_DIR}/last_swarm.slot" 2>/dev/null || true)"
    if [[ "${hour_slot}-${minute}" != "${last_swarm}" ]]; then
      "${SCRIPT_DIR}/worker_codex_swarm.sh" || true
      echo "${hour_slot}-${minute}" > "${ARMY_STATE_DIR}/last_swarm.slot"
    fi
  fi

  sleep_sec=$((60 - 10#$(date +%S)))
  sleep "${sleep_sec}"
done
