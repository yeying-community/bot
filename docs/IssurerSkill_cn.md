---

**名称**：github-issue-tool
**描述**：
用于在飞书/OpenClaw 中进行真实的 GitHub Issue 预览、创建、关闭以及执行明确的 Issue 评论。在创建/关闭操作前务必先进行预览；当目标 Issue 已明确且用户发出如 `/run` 等显式评论指令时，直接执行操作。

---

# GitHub Issue 工具

当用户希望执行以下操作时，激活此技能：

* 创建 GitHub Issue
* 关闭 GitHub Issue
* 给已有 Issue 追加明确评论（例如 `/run`）
* 查询 Issue 状态
* 处理与 GitHub Issue 相关的请求

## 必读文档

* `config/policy.json`
* `tools/github_issue_create.mjs`
* `tools/github_issue_close.mjs`
* `tools/pending_action.mjs`

## 必须遵循的创建流程

1. 尽可能通过 `repoAliases` 解析出 `owner/repo`（所有者/仓库）。
2. 起草标题（title）、正文（body）、标签（labels）和负责人（assignees）。
3. 使用 `node tools/github_issue_create.mjs ...` 进行预览。
4. 保存一个类型为 `--kind github_issue_create` 的待处理动作（pending action）。
5. 回复仓库名、标题、标签、正文，以及 `/confirm`（确认）和 `/cancel`（取消）指令。

## 必须遵循的关闭流程

1. 确定 `owner/repo` 和 `issueNumber`（Issue 编号）。
2. 默认关闭原因为 `completed`（已完成），除非明确意图为 `not_planned`（不打算做）。
3. 使用 `node tools/github_issue_close.mjs ...` 进行预览。
4. 保存一个类型为 `--kind github_issue_close` 的待处理动作。
5. 回复仓库名、Issue 编号、关闭原因，以及 `/confirm` 和 `/cancel` 指令。

## 规则

* 在常规助手路径中仅执行预览。
* 在获得明确确认之前，不得直接调用 `--execute`。
* 在同一个飞书会话范围内，新的预览应替换旧的待处理数据。

## 显式评论流程

如果用户明确要求在特定 Issue 上发布特定评论，请直接使用本地工具执行，而非通过 `gh` 命令行界面（CLI）。

**示例：**

```bash
node tools/github_issue_comment.mjs   --issueUrl https://github.com/owner/repo/issues/18   --body '/run'   --execute

```

**规则：**

* 当消息中已包含完整的 GitHub Issue 链接时，优先使用 `--issueUrl`。
* 不要要求用户执行 `gh auth login`。
* 在此工作区中，不要将 Issue 评论路由到通用的 `github` 技能。
