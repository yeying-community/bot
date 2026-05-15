# Issuer

GitHub issue orchestration service backed by OpenClaw and Feishu.

- 源代码：`workspace_assets/`
- 核心模块：`workspace_assets/tools/pending_action.mjs`、`workspace_assets/tools/github_issue_create.mjs`、`workspace_assets/tools/github_issue_update.mjs`、`workspace_assets/tools/github_issue_close.mjs`、`workspace_assets/tools/github_issue_comment.mjs`、`workspace_assets/hooks/confirmation-bridge/handler.ts`
- 配置文件：`config/`
- 运维脚本：`scripts/`
- 运行数据：`data/`
- 文档：`docs/`

## 启动方式

首次或升级后建议先做一次初始化和同步：

```bash
bash scripts/bootstrap.sh
bash scripts/sync_workspace.sh
```

手动启动：

```bash
./scripts/start_gateway.sh
./scripts/status_gateway.sh
```

如果你刚改过 `workspace_assets/`：

```bash
./scripts/sync_workspace.sh
./scripts/stop_gateway.sh
./scripts/start_gateway.sh
```

systemd 部署或升级：

```bash
BOT_USER="$(id -un)" ./scripts/install_systemd.sh
sudo systemctl restart issuer-openclaw-gateway
sudo systemctl status --no-pager issuer-openclaw-gateway
```

详细说明见：

- [部署手册](docs/部署手册.md)
- [使用手册](docs/使用手册.md)

## 排障查看

你直接这样用就行。

看总览：

```bash
cd /root/code/bot/linked-openclaw/issuer
./scripts/inspect_pending.sh summary
```

看当前所有草案：

```bash
./scripts/inspect_pending.sh list
```

只看某个仓库：

```bash
./scripts/inspect_pending.sh list --repo yeying-community/robot
```

按群查：

```bash
./scripts/inspect_pending.sh conversation --conversation-id chat:oc_xxx
```

按用户查：

```bash
./scripts/inspect_pending.sh requester --requester-id ou_xxx
```

按 `draftId` 查完整详情：

```bash
./scripts/inspect_pending.sh show --draft-id 5d496c27
```
