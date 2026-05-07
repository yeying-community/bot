#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="/root/code/bot/example/example_feishuGitIssue"
INSTANCE_DIR="$BASE_DIR/.openclaw-feishu-gitissue-gpt54"
# 停止脚本和启动脚本共用同一份实例定位信息。
CONFIG_PATH="$INSTANCE_DIR/openclaw.json"
PID_FILE="$INSTANCE_DIR/openclaw.pid"
PORT=18890

# 只杀和当前配置绑定的 openclaw，避免误伤别的实例。
find_running_pids() {
  for p in $(pgrep -x openclaw 2>/dev/null || true); do
    if [ -r "/proc/$p/environ" ] && tr '\0' '\n' < "/proc/$p/environ" | grep -q "^OPENCLAW_CONFIG_PATH=$CONFIG_PATH$"; then
      echo "$p"
    fi
  done
}

# 没有进程也没有 PID 文件时，直接认为已经停止。
pids="$(find_running_pids || true)"
if [ -z "$pids" ] && [ ! -f "$PID_FILE" ]; then
  echo "not running"
  exit 0
fi

# 先温和退出，再补一次强杀，尽量清掉残留进程。
for p in $pids; do kill "$p" 2>/dev/null || true; done
sleep 2
for p in $pids; do kill -9 "$p" 2>/dev/null || true; done

# 某些情况下 gateway 监听还在，单独按端口和进程名兜底清理。
for gp in $(ss -lntp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p && /openclaw-gatewa/ {gsub(/.*pid=/,"",$NF); gsub(/,.*/,"",$NF); print $NF}'); do
  kill "$gp" 2>/dev/null || true
  kill -9 "$gp" 2>/dev/null || true
done

rm -f "$PID_FILE"
echo "stopped"
