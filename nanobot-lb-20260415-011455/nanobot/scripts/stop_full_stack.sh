#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[deprecated] scripts/stop_full_stack.sh 已降级为兼容入口，请改用 scripts/starter.sh stop"
exec bash "$ROOT_DIR/scripts/starter.sh" stop
