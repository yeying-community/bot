#!/usr/bin/env bash
set -euo pipefail
INSTANCE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$INSTANCE_DIR/config/openclaw.json}"
STATE_DIR="${OPENCLAW_STATE_DIR:-$INSTANCE_DIR/state}"
LOG_PATH="$INSTANCE_DIR/gateway.out"
PORT="${OPENCLAW_GATEWAY_PORT:-18830}"

echo "instance_dir=$INSTANCE_DIR"
echo "config_path=$CONFIG_PATH"
echo "state_dir=$STATE_DIR"

echo "== process (by config path) =="
found=0
for p in $(pgrep -x openclaw 2>/dev/null || true); do
  if [ -r "/proc/$p/environ" ] && tr '\0' '\n' < "/proc/$p/environ" | grep -q "^OPENCLAW_CONFIG_PATH=$CONFIG_PATH$"; then
    found=1
    echo "openclaw pid=$p"
    ps -fp "$p" || true
  fi
done
if [ "$found" -eq 0 ]; then
  echo "openclaw not running"
fi

echo "== port =="
ss -lntp | grep -E "127.0.0.1:$PORT|\[::1\]:$PORT" || true

echo "== channel capabilities =="
OPENCLAW_CONFIG_PATH="$CONFIG_PATH" OPENCLAW_STATE_DIR="$STATE_DIR" openclaw channels capabilities --json 2>/dev/null || true

echo "== key config =="
OPENCLAW_CONFIG_PATH="$CONFIG_PATH" OPENCLAW_STATE_DIR="$STATE_DIR" openclaw config get agents.defaults.model.primary 2>/dev/null || true
OPENCLAW_CONFIG_PATH="$CONFIG_PATH" OPENCLAW_STATE_DIR="$STATE_DIR" openclaw config get channels.feishu.requireMention 2>/dev/null || true
OPENCLAW_CONFIG_PATH="$CONFIG_PATH" OPENCLAW_STATE_DIR="$STATE_DIR" openclaw config get channels.feishu.groupAllowFrom 2>/dev/null || true

echo "== recent log =="
tail -n 120 "$LOG_PATH" 2>/dev/null || true
