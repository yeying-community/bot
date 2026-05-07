#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/watchdog.sh"
"${SCRIPT_DIR}/worker_observe.sh"
"${SCRIPT_DIR}/worker_verify.sh"
"${SCRIPT_DIR}/worker_codex_advisor.sh" || true
"${SCRIPT_DIR}/status_army.sh"
