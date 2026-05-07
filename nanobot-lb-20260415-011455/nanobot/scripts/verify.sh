#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_TO="${VERIFY_TEST_TO:-+15555550123}"

"${SCRIPT_DIR}/doctor.sh"

status_out="$(openclaw channels status 2>&1 || true)"
if grep -Eq 'linked.*running.*connected|running.*connected.*linked' <<<"${status_out}"; then
  echo "[ok] WhatsApp channel looks connected"
else
  echo "[fail] WhatsApp channel not fully connected" >&2
  echo "${status_out}" >&2
  exit 3
fi

agent_out="$(openclaw agent --local --to "${TEST_TO}" --message "ping" --thinking off --timeout 120 --json 2>&1 || true)"
if grep -Eq '"payloads"|HEARTBEAT_OK|"text"' <<<"${agent_out}"; then
  echo "[ok] local agent call returned"
else
  echo "[fail] local agent call failed" >&2
  echo "${agent_out}" >&2
  exit 4
fi

echo "[ok] verify passed"
