#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

if [[ "${ARMY_ENABLE_CODEX}" != "1" || "${ARMY_ENABLE_SWARM}" != "1" ]]; then
  exit 0
fi

if ! command -v "${CODEX_BIN}" >/dev/null 2>&1; then
  append_pending "swarm" "codex_missing" "install_codex_cli"
  exit 1
fi

latest_report="$(ls -1t "${REPORT_DIR}"/observe-*.md "${REPORT_DIR}"/verify-*.md 2>/dev/null | head -n 1 || true)"
if [[ -z "${latest_report}" ]]; then
  append_pending "swarm" "no_report" "run_worker_observe"
  exit 1
fi

ts="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "${ADVISOR_DIR}/swarm-${ts}"

run_role() {
  local role="$1"
  local prompt="$2"
  local out="${ADVISOR_DIR}/swarm-${ts}/${role}.md"
  local log="${ADVISOR_DIR}/swarm-${ts}/${role}.log"
  run_with_timeout "${ARMY_CODEX_TIMEOUT_SEC}" "${CODEX_BIN}" exec -C "${BOT_ROOT}" -s "${ARMY_CODEX_SANDBOX}" --skip-git-repo-check -o "${out}" "${prompt}" > "${log}" 2>&1 || true
}

run_role ops "你是运维指挥官。阅读 ${latest_report}，给出仅跨境电商场景的稳定性改进建议（P0/P1）。"
run_role product "你是产品负责人。阅读 ${latest_report}，给出跨境电商对话能力改进（价格、MOQ、交期、升级老板）。"
run_role qa "你是测试负责人。阅读 ${latest_report}，给出可执行验收用例与回归策略。"

printf '[%s] swarm generated at %s\n' "$(timestamp)" "${ADVISOR_DIR}/swarm-${ts}" | tee -a "${ADVISOR_LOG}"
