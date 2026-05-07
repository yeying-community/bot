#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_WORKSPACE="${1:-/root/code/bot/example/example_feishuGitIssue/.openclaw-feishu-gitissue-gpt54/workspace-larkbot}"

# 这里把仓库里的 workspace_assets 镜像到实际运行 workspace。
mkdir -p "$TARGET_WORKSPACE/tools/lib"
mkdir -p "$TARGET_WORKSPACE/skills"
mkdir -p "$TARGET_WORKSPACE/hooks"
mkdir -p "$TARGET_WORKSPACE/config"
mkdir -p "$TARGET_WORKSPACE/state/pending-actions"

# tools、skills 和 hooks 都直接按目录复制，保持示例内容和运行时一致。
cp -R "$ROOT_DIR/workspace_assets/tools/." "$TARGET_WORKSPACE/tools/"
cp -R "$ROOT_DIR/workspace_assets/skills/." "$TARGET_WORKSPACE/skills/"
cp -R "$ROOT_DIR/workspace_assets/hooks/." "$TARGET_WORKSPACE/hooks/"

if [ ! -f "$TARGET_WORKSPACE/config/policy.json" ]; then
# 只有缺失时才落默认 policy，避免覆盖用户自定义规则。
  cp "$ROOT_DIR/config/policy.example.json" "$TARGET_WORKSPACE/config/policy.json"
fi

echo "synced workspace assets to: $TARGET_WORKSPACE"
echo "next:"
echo "  1. edit $TARGET_WORKSPACE/config/policy.json"
echo "  2. ensure /root/.config/openclaw/github-app/config.env is present"
echo "  3. start or restart: bash $ROOT_DIR/start_gitissue_gpt54.sh"
