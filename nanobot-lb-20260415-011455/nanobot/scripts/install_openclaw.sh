#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[deprecated] scripts/install_openclaw.sh -> scripts/setup/openclaw_prepare.sh install"
exec bash "$ROOT_DIR/scripts/setup/openclaw_prepare.sh" install "$@"
