#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[deprecated] scripts/apply_whatsapp_patch.sh -> scripts/setup/openclaw_prepare.sh patch"
exec bash "$ROOT_DIR/scripts/setup/openclaw_prepare.sh" patch "$@"
