#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[deprecated] scripts/configure_openclaw.sh -> scripts/setup/openclaw_prepare.sh configure"
exec bash "$ROOT_DIR/scripts/setup/openclaw_prepare.sh" configure "$@"
