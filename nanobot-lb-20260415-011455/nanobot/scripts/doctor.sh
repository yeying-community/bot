#!/usr/bin/env bash
set -euo pipefail

ROUTER_BASE_URL="${ROUTER_BASE_URL:-https://test-router.yeying.pub/v1}"
ROUTER_MODEL="${ROUTER_MODEL:-gpt-5.3-codex}"

echo "[check] whoami=$(whoami) host=$(hostname)"

if command -v node >/dev/null 2>&1; then
  echo "[check] node=$(node -v)"
else
  echo "[fail] node missing" >&2
  exit 2
fi

if command -v openclaw >/dev/null 2>&1; then
  echo "[check] openclaw=$(openclaw --version)"
else
  echo "[fail] openclaw missing" >&2
  exit 2
fi

if [[ -n "${ROUTER_API_KEY:-}" ]]; then
  echo "[check] router models"
  models_out="$(curl -fsS "${ROUTER_BASE_URL}/models" -H "Authorization: Bearer ${ROUTER_API_KEY}")"
  if grep -q "${ROUTER_MODEL}" <<<"${models_out}"; then
    echo "[ok] model ${ROUTER_MODEL} found"
  else
    echo "[warn] model ${ROUTER_MODEL} not found in /models"
  fi
else
  echo "[warn] ROUTER_API_KEY not set, skip router checks"
fi

echo "[check] channels status"
openclaw channels status || true

if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  echo "[check] gateway health"
  openclaw gateway --token "${OPENCLAW_GATEWAY_TOKEN}" health || true
else
  echo "[warn] OPENCLAW_GATEWAY_TOKEN not set, skip gateway health"
fi

echo "[ok] doctor finished"
