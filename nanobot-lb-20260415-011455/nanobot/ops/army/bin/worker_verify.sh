#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

ts="$(date '+%Y%m%d-%H%M%S')"
report="${REPORT_DIR}/verify-${ts}.md"

doctor_ok=1
doctor_out=""
if doctor_out="$(bash "${BOT_ROOT}/scripts/doctor.sh" 2>&1)"; then
  doctor_ok=1
else
  doctor_ok=0
fi

status_text="$(channel_status)"
connected_ok=0
if channel_is_connected "${status_text}"; then
  connected_ok=1
fi

{
  echo "# Verify Report ${ts}"
  echo
  echo "- doctor_ok: ${doctor_ok}"
  echo "- connected_ok: ${connected_ok}"
  echo
  echo "## doctor_output"
  echo '```text'
  printf '%s\n' "${doctor_out}"
  echo '```'
  echo
  echo "## channel_status"
  echo '```text'
  printf '%s\n' "${status_text}"
  echo '```'
} > "${report}"

cp "${report}" "${REPORT_DIR}/latest-verify.md"
printf '[%s] wrote %s\n' "$(timestamp)" "${report}" | tee -a "${VERIFY_LOG}"

if [[ "${doctor_ok}" -ne 1 || "${connected_ok}" -ne 1 ]]; then
  append_pending "verify" "verify_failed" "check_report_${report##*/}"
fi
