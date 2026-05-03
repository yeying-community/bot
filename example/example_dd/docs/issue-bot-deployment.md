# Issue 机器人部署手册

## 1. 适用范围

本文中的“issue 机器人”指当前仓库里已经落地的 `dd-bot` GitHub Issue 能力，目录在 `example/example_dd/`。

当前实现不是一个独立的 issue-only 服务，而是这条现有链路：

`DingTalk -> OpenClaw dingtalk channel -> OpenClaw workspace tools -> GitHub Issues`

部署完成后，机器人可以：

- 在群里识别“提 issue / 跟踪 bug / 生成任务”这类请求
- 先生成 Issue 草稿和预览
- 在发起人或管理员确认后调用 GitHub API 创建真实 Issue

## 2. 部署前置条件

### 2.1 运行环境

- Linux 或 WSL2
- `Node.js >= 22`
- `npm`
- `openclaw` 可执行命令

如果目标机还没有安装 `openclaw`，可在仓库根目录执行：

```bash
bash scripts/setup/openclaw_prepare.sh install
```

安装完成后确认：

```bash
node -v
npm -v
openclaw --version
```

### 2.2 外部系统准备

- 一个可用的钉钉应用机器人，并拿到 `DINGTALK_CLIENT_ID` / `DINGTALK_CLIENT_SECRET`
- 一个可用的 Router key，即 `ROUTER_API_KEY`
- 一个对目标仓库具备 Issue 写入能力的 `GITHUB_TOKEN`
- 至少一个默认目标仓库：`GITHUB_DEFAULT_OWNER` + `GITHUB_DEFAULT_REPO`

### 2.3 平台限制

- 当前路线是钉钉应用机器人
- 群聊里只有 `@机器人` 的消息才会被钉钉投递给机器人
- 仓库没有提供独立的 systemd / supervisor 配置，默认启动方式是前台运行 `openclaw gateway run`

## 3. 安装与启动步骤

### 3.1 进入目录

```bash
cd /home/zb/yeying-community/robot/coding-bot/data/repos/yeying-community__robot/repo/example/example_dd
```

### 3.2 准备本地配置

```bash
cp .env.template .env.local
```

至少补齐这些变量：

```dotenv
DINGTALK_CLIENT_ID=your_dingtalk_client_id
DINGTALK_CLIENT_SECRET=your_dingtalk_client_secret
ROUTER_API_KEY=your_router_api_key
GITHUB_TOKEN=your_github_token
GITHUB_DEFAULT_OWNER=your_org_or_user
GITHUB_DEFAULT_REPO=your_repo
```

如果希望启用备用模型，再补：

```dotenv
DASHSCOPE_API_KEY=your_dashscope_api_key
```

### 3.3 可选：准备策略文件

默认策略文件是 `config/policy.example.json`。如果需要自定义管理员、确认人或仓库映射，推荐复制后再改：

```bash
cp config/policy.example.json config/policy.local.json
```

然后在 `.env.local` 里指定：

```dotenv
DD_POLICY_PATH=config/policy.local.json
```

重点关注这些策略项：

- `admins`：群里的管理员身份
- `writeAccess.confirmers`：谁可以确认执行
- `routing.githubRepos`：仓库别名到 `owner/repo` 的映射

### 3.4 写入 OpenClaw 配置并同步 workspace

```bash
bash scripts/configure_openclaw_dingtalk.sh
```

这个脚本会自动完成：

- 校验 `ROUTER_API_KEY`、`DINGTALK_CLIENT_ID`、`DINGTALK_CLIENT_SECRET`
- 安装并启用 `dingtalk` 插件
- 写入 Router 主模型与 DashScope fallback
- 同步 `skills`、`tools`、`hooks`、`policy`
- 构建 `~/.openclaw/workspace-dd-bot/kb/index`

如果后续只改了知识、策略或工具，不需要重新配通道，可单独执行：

```bash
bash scripts/sync_openclaw_workspace.sh
```

### 3.5 启动机器人

```bash
bash scripts/run_openclaw_gateway.sh
```

当前脚本以前台方式运行。手工停止可直接 `Ctrl+C`；如果你用 `tmux`、`systemd` 或其他宿主机进程管理器托管，也只需要托管这一条启动命令。

### 3.6 最小自检

先检查 OpenClaw 状态：

```bash
openclaw health
openclaw channels status
```

再做一次 Issue 预览 smoke test：

```bash
node ~/.openclaw/workspace-dd-bot/tools/github_issue_create.mjs \
  --title "部署联调测试" \
  --body "用于验证 issue 机器人部署是否完成"
```

预期结果：

- 返回 `mode: "preview"`
- 返回 `.env.local` 中配置的默认 `owner/repo`

建议再运行一次仓库自带校验：

```bash
bash scripts/verify_openclaw_tool_previews.sh
bash scripts/verify_openclaw_confirmation_loop.sh
bash scripts/verify_confirmation_bridge_hook.sh
```

## 4. 配置项与环境变量

### 4.1 必填环境变量

| 变量 | 用途 | 说明 |
| --- | --- | --- |
| `DINGTALK_CLIENT_ID` | 钉钉通道接入 | `configure_openclaw_dingtalk.sh` 强校验 |
| `DINGTALK_CLIENT_SECRET` | 钉钉通道接入 | `configure_openclaw_dingtalk.sh` 强校验 |
| `ROUTER_API_KEY` | 主模型访问凭证 | `configure_openclaw_dingtalk.sh` 强校验 |
| `GITHUB_TOKEN` | 真实创建 Issue | 仅预览时不需要，执行创建时必须提供 |
| `GITHUB_DEFAULT_OWNER` | 默认 GitHub owner | Issue 工具未显式传参时优先使用 |
| `GITHUB_DEFAULT_REPO` | 默认 GitHub repo | Issue 工具未显式传参时优先使用 |

### 4.2 常用可选环境变量

| 变量 | 用途 | 默认值 / 备注 |
| --- | --- | --- |
| `ROUTER_BASE_URL` | Router 地址 | 默认 `https://test-router.yeying.pub/v1` |
| `ROUTER_MODEL` | 主模型名 | 默认 `gpt-5.3-codex` |
| `DASHSCOPE_API_KEY` | 备用模型凭证 | 不填则不启用 fallback |
| `DASHSCOPE_BASE_URL` | DashScope 地址 | 默认官方兼容端点 |
| `DASHSCOPE_MODEL` | 备用模型名 | 默认 `qwen3-coder-plus` |
| `DD_POLICY_PATH` | 运行时策略文件 | 默认 `config/policy.example.json` |
| `GITHUB_OWNER` | 兼容仓库 owner | 仅作为 Issue 工具的后备值 |
| `GITHUB_REPO` | 兼容仓库 repo | 仅作为 Issue 工具的后备值 |

### 4.3 运行时关键目录

| 路径 | 作用 |
| --- | --- |
| `~/.openclaw/workspace-dd-bot/tools/` | Issue、日程、审计等工具 |
| `~/.openclaw/workspace-dd-bot/policy/runtime-policy.json` | 当前生效策略 |
| `~/.openclaw/workspace-dd-bot/state/pending-actions/` | 待确认执行动作 |
| `~/.openclaw/workspace-dd-bot/state/audit/events.jsonl` | 审计日志 |
| `~/.openclaw/workspace-dd-bot/kb/index/` | 本地知识索引 |

## 5. 日常运维

### 5.1 常用命令

```bash
# 重新同步知识、策略、工具
bash scripts/sync_openclaw_workspace.sh

# 查看知识索引状态
node ~/.openclaw/workspace-dd-bot/tools/knowledge_index.mjs --action status

# 查看待执行动作
node ~/.openclaw/workspace-dd-bot/tools/pending_action.mjs --action get

# 清理当前会话的待执行动作
node ~/.openclaw/workspace-dd-bot/tools/pending_action.mjs --action clear

# 查看审计日志
node ~/.openclaw/workspace-dd-bot/tools/audit_log.mjs --action list
```

### 5.2 推荐运维动作

- 改了 `.env.local` 后，重新执行 `bash scripts/configure_openclaw_dingtalk.sh`
- 改了 `docs_source/`、`workspace_assets/` 或策略文件后，重新执行 `bash scripts/sync_openclaw_workspace.sh`
- 每次发版前至少跑 `verify_openclaw_tool_previews.sh` 和 `verify_openclaw_confirmation_loop.sh`

## 6. 常见问题与排查

### 6.1 `openclaw: command not found`

排查步骤：

```bash
node -v
npm config get prefix
openclaw --version
```

如果 `openclaw` 未安装，回到仓库根目录执行：

```bash
bash scripts/setup/openclaw_prepare.sh install
```

### 6.2 `ROUTER_API_KEY is required` 或 `DINGTALK_CLIENT_ID is required`

说明 `.env.local` 缺少必填项，或 shell 没有正确读取该文件。

排查步骤：

```bash
grep -E '^(ROUTER_|DINGTALK_|GITHUB_)' .env.local
bash scripts/configure_openclaw_dingtalk.sh
```

### 6.3 机器人在群里没有响应

优先检查：

- 是否是钉钉群聊
- 是否 `@` 了机器人
- `openclaw channels status` 是否显示 `dingtalk` 已启用
- `DINGTALK_CLIENT_ID` / `DINGTALK_CLIENT_SECRET` 是否填写正确

### 6.4 Issue 能预览，但不能真实创建

常见原因：

- 没有配置 `GITHUB_TOKEN`
- 没有配置 `GITHUB_DEFAULT_OWNER` / `GITHUB_DEFAULT_REPO`
- Token 对目标仓库没有足够权限

可直接执行下面命令定位：

```bash
node ~/.openclaw/workspace-dd-bot/tools/github_issue_create.mjs \
  --title "执行模式排查" \
  --body "仅用于部署排查" \
  --execute
```

如果报仓库不明确，检查 `.env.local` 和 `routing.githubRepos`。

### 6.5 群里回复“确认执行”后没有创建 Issue

优先检查待执行动作是否真的已写入：

```bash
node ~/.openclaw/workspace-dd-bot/tools/pending_action.mjs --action get
```

再检查审计日志里是否有拒绝记录：

```bash
node ~/.openclaw/workspace-dd-bot/tools/audit_log.mjs --action list
```

常见原因：

- 发起人没有先走“预览 -> pending action”
- 当前确认人不在 `writeAccess.confirmers` 允许范围内
- `admins` 配置不正确

### 6.6 改了策略或知识后，机器人仍然按旧规则运行

重新同步并确认索引状态：

```bash
bash scripts/sync_openclaw_workspace.sh
node ~/.openclaw/workspace-dd-bot/tools/knowledge_index.mjs --action status
```

如果 `runtime-policy.json` 没更新，优先检查 `DD_POLICY_PATH` 是否仍指向旧文件。
