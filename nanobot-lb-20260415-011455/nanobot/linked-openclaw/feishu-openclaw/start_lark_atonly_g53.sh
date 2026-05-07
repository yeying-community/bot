#!/usr/bin/env bash
set -euo pipefail
INSTANCE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$INSTANCE_DIR/config/openclaw.json}"
STATE_DIR="${OPENCLAW_STATE_DIR:-$INSTANCE_DIR/state}"
LOG_PATH="$INSTANCE_DIR/gateway.out"
PID_FILE="$INSTANCE_DIR/openclaw.pid"
PORT="${OPENCLAW_GATEWAY_PORT:-18830}"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "missing config: $CONFIG_PATH"
  echo "create it from: $INSTANCE_DIR/config/openclaw.json.template"
  exit 1
fi

find_running_pids() {
  for p in $(pgrep -x openclaw 2>/dev/null || true); do
    if [ -r "/proc/$p/environ" ] && tr '\0' '\n' < "/proc/$p/environ" | grep -q "^OPENCLAW_CONFIG_PATH=$CONFIG_PATH$"; then
      echo "$p"
    fi
  done
}

if pids="$(find_running_pids || true)"; then
  if [ -n "${pids:-}" ] && ss -lntp | grep -q "127.0.0.1:$PORT"; then
    echo "already running: pids=$pids"
    exit 0
  fi
fi

if [ -n "${pids:-}" ]; then
  for p in $pids; do kill "$p" 2>/dev/null || true; done
  sleep 1
fi

mkdir -p "$STATE_DIR"
nohup env OPENCLAW_CONFIG_PATH="$CONFIG_PATH" OPENCLAW_STATE_DIR="$STATE_DIR" \
  openclaw gateway run --port "$PORT" >> "$LOG_PATH" 2>&1 &
echo $! > "$PID_FILE"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  pids_now="$(find_running_pids || true)"
  if [ -n "$pids_now" ] && ss -lntp | grep -q "127.0.0.1:$PORT"; then
    echo "started: pids=$pids_now"
    exit 0
  fi
done

echo "start failed; tail log:" >&2
tail -n 140 "$LOG_PATH" >&2 || true
exit 1
