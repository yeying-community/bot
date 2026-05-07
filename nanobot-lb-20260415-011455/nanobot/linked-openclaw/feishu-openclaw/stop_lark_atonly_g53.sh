#!/usr/bin/env bash
set -euo pipefail
INSTANCE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$INSTANCE_DIR/config/openclaw.json}"
PID_FILE="$INSTANCE_DIR/openclaw.pid"
PORT="${OPENCLAW_GATEWAY_PORT:-18830}"

find_running_pids() {
  for p in $(pgrep -x openclaw 2>/dev/null || true); do
    if [ -r "/proc/$p/environ" ] && tr '\0' '\n' < "/proc/$p/environ" | grep -q "^OPENCLAW_CONFIG_PATH=$CONFIG_PATH$"; then
      echo "$p"
    fi
  done
}

pids="$(find_running_pids || true)"
if [ -z "$pids" ] && [ ! -f "$PID_FILE" ]; then
  echo "not running"
  exit 0
fi

for p in $pids; do
  kill "$p" 2>/dev/null || true
done
sleep 2
for p in $pids; do
  kill -9 "$p" 2>/dev/null || true
done

for gp in $(ss -lntp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p && /openclaw-gatewa/ {gsub(/.*pid=/,"",$NF); gsub(/,.*/,"",$NF); print $NF}'); do
  kill "$gp" 2>/dev/null || true
  kill -9 "$gp" 2>/dev/null || true
done

rm -f "$PID_FILE"
echo "stopped"
