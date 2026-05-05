# Issue #18 联调记录

## 背景

本次联调目标是确认 GitHub Issue 机器人与代码机器人之间的协作链路是否连通，并沉淀问题与后续优化项。

本记录基于当前仓库代码阅读和本次 Issue #18 已被代码机器人接收处理这一事实整理，不包含真实 GitHub App 凭据、飞书群消息和线上部署环境的实机冒烟结果。

## 联调范围

- Issue 创建链路：`example/example_feishuGitIssue/`
- Issue 评论触发链路：`github_issue_comment.mjs --body '/run'`
- 代码机器人读取与执行链路：`coding-bot/issue_bot_service.py`

## 联调链路记录

### 1. Issue 机器人侧

- `example/example_feishuGitIssue/workspace_assets/skills/github-issue-tool/SKILL.md` 已定义 GitHub Issue 创建、关闭和明确评论三类动作。
- `example/example_feishuGitIssue/workspace_assets/tools/github_issue_comment.mjs` 支持直接对指定 Issue 发表评论，能够用于发送 `/run` 这类显式触发指令。
- `docs/github机器人部署手册.md` 已给出预览、创建、关闭和飞书侧最小冒烟步骤，说明 Issue 机器人链路在文档层面是闭合的。

### 2. 代码机器人侧

- `coding-bot/issue_bot_service.py` 默认将 `TRIGGER_COMMENT` 设为 `/run`，与 Issue 机器人显式评论动作能够对接。
- 同文件中的 `should_trigger_event` 和轮询逻辑会识别 `issue_comment.created` 事件，并将命中的 Issue 写入队列。
- `build_prompt` 会把 Issue 标题、正文、本地仓库路径和执行约束一并传给代码机器人。
- `parse_codex_result` 强制要求代码机器人以 `result: succeeded | no_change | needs_human` 的结构返回，便于外层机器人继续处理。

### 3. 本次联调结论

- 当前 Issue #18 能被代码机器人接收并进入处理流程，说明 “GitHub Issue -> 代码机器人” 这段链路已打通。
- Issue 机器人发送 `/run`，代码机器人读取 `/run` 的协作契约在代码和文档里都存在。
- 当前仓库已经具备从 Issue 操作到代码处理的最小闭环，但联调入口仍分散在多个目录和文档中。

## 发现的问题

1. 端到端联调说明分散在 `docs/github机器人部署手册.md`、`example/example_feishuGitIssue/README.md`、`coding-bot/README.md` 等多处，新接手的人需要自行拼接完整流程。
2. `/run` 作为跨机器人交接指令，当前主要依赖默认约定，分散出现在示例工具、技能说明、部署文档和代码机器人配置中，缺少统一的联调入口说明。
3. 仓库内没有一份专门面向 “Issue 机器人 -> 代码机器人” 的联调记录模板，后续每次联调的现象、问题和结论容易散落在 issue 评论里。
4. 当前仓库主要提供人工操作说明，没有覆盖 “创建 issue -> 评论 `/run` -> 观察代码机器人状态” 的统一自检脚本或检查清单。

## 后续优化项

1. 增加一份面向双机器人协作的单页联调手册，把创建 issue、追加 `/run`、观察代码机器人处理结果串成一条顺序流程。
2. 在联调手册或示例配置中显式标注 `/run` 是默认交接指令，并说明当 `TRIGGER_COMMENT` 被修改时，Issue 机器人侧也要同步调整。
3. 补一份轻量联调模板，固定记录时间、仓库、Issue 编号、触发方式、观察结果、问题和结论，减少重复整理成本。
4. 增加最小化联合自检清单，至少覆盖创建预览、Issue 评论触发、代码机器人入队和最终结果状态四个观察点。

## 备注

- 本次记录确认了仓库内联调设计与当前处理链路。
- 真实飞书消息、GitHub App 权限、外部服务可用性仍需在部署环境中按现有手册完成一次实机冒烟。
