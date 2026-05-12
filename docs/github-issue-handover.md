# GitHub Issue Bot Handover

This document is for engineers taking over `example/example_feishuGitIssue/`.
It focuses on implementation details, source-of-truth files, runtime evidence,
and current gaps. It is intentionally ASCII-only because the current remote
terminal setup does not safely preserve Chinese text in tracked markdown files.

This document answers four questions:

- What was added on top of a basic Feishu OpenClaw bot.
- Which files are the real control points for the GitHub Issue bot.
- Which flows are already implemented in code, not only in design.
- Where the current implementation is weak or non-deterministic.

## 1. Scope and current capability boundary

As of this handover, the bot supports only three concrete GitHub actions:

- Draft and create a GitHub issue after `/confirm` or `/submit`.
- Draft and close a GitHub issue after `/confirm` or `/submit`.
- Directly comment on an already specified issue, for example posting `/run`.

Evidence:

- `example/example_feishuGitIssue/README.md:5-16`
- `example/example_feishuGitIssue/workspace_assets/tools/github_issue_create.mjs:46-97`
- `example/example_feishuGitIssue/workspace_assets/tools/github_issue_close.mjs:59-115`
- `example/example_feishuGitIssue/workspace_assets/tools/github_issue_comment.mjs:69-121`
- `example/example_feishuGitIssue/workspace_assets/tools/lib/github_app.mjs:147-219`

Important boundary: this repo still has no inbound GitHub event pipeline.
It does not listen to GitHub comments, does not consume a GitHub webhook,
and does not auto-close issues because another bot commented `/submit`.

Evidence:

- `example/example_feishuGitIssue/README.md:15`
- `example/example_feishuGitIssue/README.md:37-40`

## 2. What was added beyond a basic Feishu OpenClaw bot

A minimal Feishu OpenClaw bot gives you message ingress, model execution,
and message egress. The GitHub Issue bot becomes a real issue bot only because
five additional layers were added.

### 2.1 Dedicated instance and dedicated workspace

- `openclaw.example.json:28-37` binds the default workspace to the GitHub Issue bot runtime workspace.
- `start_gitissue_gpt54.sh:4-13` binds instance path, state path, log path, pid file, port, and GitHub env file.
- `start_gitissue_gpt54.sh:85-89` starts the gateway with those paths pinned to this instance.
- `scripts/sync_to_feishu_workspace.sh:7-22` copies the repo-owned `workspace_assets` into the live OpenClaw workspace.

This is the first major change from a generic bot: messages no longer enter a
blank workspace. They enter a GitHub Issue-specific runtime workspace.

### 2.2 Local GitHub App authentication library

The most important non-OpenClaw addition is the local GitHub App auth layer:

- `workspace_assets/tools/lib/github_app.mjs:11-59` reads `/root/.config/openclaw/github-app/config.env` and normalizes legacy env names.
- `workspace_assets/tools/lib/github_app.mjs:61-76` supports either PEM content or a private-key file path.
- `workspace_assets/tools/lib/github_app.mjs:147-175` implements private key -> app JWT -> installation token.
- `workspace_assets/tools/lib/github_app.mjs:177-219` exposes `resolveGitHubToken()` for all GitHub write tools.
- `start_gitissue_gpt54.sh:30-42` normalizes legacy `GITHUB_APP_PRIVATE_KEY=/path/to/pem` into `GITHUB_APP_PRIVATE_KEY_PATH`.

Without this layer, the bot would fall back to `gh auth login` or a manually
managed PAT. With this layer, it can reuse the existing GitHub App setup.

### 2.3 Local GitHub Issue tools

Instead of letting the model improvise raw GitHub CLI commands, the repo adds
explicit local tools:

- `workspace_assets/tools/github_issue_create.mjs`
- `workspace_assets/tools/github_issue_close.mjs`
- `workspace_assets/tools/github_issue_comment.mjs`

Create and close default to preview mode:

- `github_issue_create.mjs:8-44`
- `github_issue_close.mjs:20-57`

Comment is allowed to execute directly for an explicit issue target:

- `github_issue_comment.mjs:29-67`
- `github_issue_comment.mjs:69-121`

### 2.4 Pending-action state machine

The real safety mechanism is not prompt text. It is the persisted pending-action layer:

- `workspace_assets/tools/pending_action.mjs:21-27` defines the pending state directory.
- `workspace_assets/tools/pending_action.mjs:94-120` reads, writes, and clears pending JSON by conversation scope.
- `workspace_assets/tools/pending_action.mjs:122-146` maps a pending kind to a real execution tool.
- `workspace_assets/tools/pending_action.mjs:153-177` stores preview state without causing external side effects.
- `workspace_assets/tools/pending_action.mjs:204-247` executes the real GitHub mutation only after confirmation.

This is the key change that separates “model drafted something” from “GitHub was mutated”.

### 2.5 Feishu confirmation bridge

The `/confirm`, `/submit`, and `/cancel` behavior is implemented by code, not only prompt rules:

- `workspace_assets/hooks/confirmation-bridge/handler.ts:38-41` only intercepts Feishu message-received events.
- `workspace_assets/hooks/confirmation-bridge/handler.ts:57-68` loads confirm and cancel commands.
- `workspace_assets/hooks/confirmation-bridge/handler.ts:76-98` enforces requester/admin authorization.
- `workspace_assets/hooks/confirmation-bridge/handler.ts:127-130` ignores non-confirm and non-cancel messages.
- `workspace_assets/hooks/confirmation-bridge/handler.ts:148-152` returns silently when no pending action exists.
- `workspace_assets/hooks/confirmation-bridge/handler.ts:172-190` dispatches to `pending_action.mjs --action execute`.

This is the second major change from a generic bot: confirmation commands bypass
normal free-form dialogue and go through a fixed code path.

## 3. The actual runtime flows

### 3.1 Create issue flow

The create flow is implemented as “dedicated workspace + skill guidance + local tool execution”:

1. Feishu messages enter the dedicated instance. Evidence: `openclaw.example.json:52-87` and `start_gitissue_gpt54.sh:88-89`.
2. Workspace rules tell the agent to load the GitHub issue skill for issue work. Evidence: `.openclaw-feishu-gitissue-gpt54/workspace-larkbot/AGENTS.md:13-20`.
3. The skill requires preview first, then pending save. Evidence: `workspace_assets/skills/github-issue-tool/SKILL.md:24-30`.
4. `github_issue_create.mjs` returns only the structured payload when `--execute` is absent. Evidence: `workspace_assets/tools/github_issue_create.mjs:34-44`.
5. `pending_action.mjs --action create` persists the pending action for the current Feishu conversation. Evidence: `workspace_assets/tools/pending_action.mjs:153-177`.
6. `/confirm` or `/submit` is intercepted by the confirmation hook. Evidence: `workspace_assets/hooks/confirmation-bridge/handler.ts:127-190`.
7. `pending_action.mjs` dispatches `github_issue_create.mjs --execute`. Evidence: `workspace_assets/tools/pending_action.mjs:122-146` and `204-247`.
8. `github_issue_create.mjs` calls `resolveGitHubToken()` and then `POST /repos/{owner}/{repo}/issues`. Evidence: `workspace_assets/tools/github_issue_create.mjs:46-97`.

Runtime evidence:

- Preview and pending save: `example/example_feishuGitIssue/.openclaw-feishu-gitissue-gpt54/state/agents/main/sessions/959c349f-1f7b-429a-8e59-943f3071d3ce.jsonl.comment-reset.bak:23-27`
- Confirmed execution creating issue `#18`: `example/example_feishuGitIssue/.openclaw-feishu-gitissue-gpt54/state/agents/main/sessions/959c349f-1f7b-429a-8e59-943f3071d3ce.jsonl.comment-reset.bak:30-31`

### 3.2 Close issue flow

The close flow reuses the same pending-and-confirm mechanism:

- `workspace_assets/skills/github-issue-tool/SKILL.md:32-38` requires preview before close.
- `workspace_assets/tools/github_issue_close.mjs:31-57` exposes preview mode for the PATCH target.
- `workspace_assets/tools/github_issue_close.mjs:59-115` executes `PATCH /issues/{issueNumber}`.
- `workspace_assets/tools/pending_action.mjs:125-128` maps `github_issue_close` to `github_issue_close.mjs`.

Runtime evidence:

- Successful close of issue `#18`: `example/example_feishuGitIssue/.openclaw-feishu-gitissue-gpt54/state/agents/main/sessions/e5971aca-20ea-47ee-b708-292edcbb27ff.jsonl:27`

### 3.3 Direct issue comment flow

Commenting is intentionally the only direct-write path when the user has already
specified a concrete issue target and a concrete comment body:

- `workspace_assets/skills/github-issue-tool/SKILL.md:47-61` says explicit issue comments should use the local comment tool, not `gh` CLI.
- `.openclaw-feishu-gitissue-gpt54/workspace-larkbot/AGENTS.md:22` calls out explicit issue comments as a special case.
- `workspace_assets/tools/github_issue_comment.mjs:6-17` parses an issue URL into owner/repo/issue number.
- `workspace_assets/tools/github_issue_comment.mjs:69-121` executes `POST /issues/{issueNumber}/comments`.

Runtime evidence:

- Successful `/run` comment on issue `#17`: `example/example_feishuGitIssue/.openclaw-feishu-gitissue-gpt54/state/agents/main/sessions/071306c8-eae8-413c-a6c3-23ce22d9d646.jsonl:8-10`

## 4. The most important files to read first

If the next maintainer is short on time, read these first, in order:

1. `example/example_feishuGitIssue/workspace_assets/tools/lib/github_app.mjs`
2. `example/example_feishuGitIssue/workspace_assets/tools/pending_action.mjs`
3. `example/example_feishuGitIssue/workspace_assets/hooks/confirmation-bridge/handler.ts`
4. `example/example_feishuGitIssue/workspace_assets/tools/github_issue_create.mjs`
5. `example/example_feishuGitIssue/workspace_assets/tools/github_issue_close.mjs`
6. `example/example_feishuGitIssue/workspace_assets/skills/github-issue-tool/SKILL.md`
7. `example/example_feishuGitIssue/start_gitissue_gpt54.sh`

Why these matter:

- `github_app.mjs` is the trust root for GitHub write access.
- `pending_action.mjs` is the trust root for safe confirmation behavior.
- `handler.ts` is the bridge between Feishu confirm commands and real mutations.
- create/close/comment tools are the actual GitHub side-effect endpoints.
- the skill and runtime workspace instructions decide whether the agent picks the correct local tools.

## 5. The biggest current weaknesses

### 5.1 The bot does not have deterministic intent routing for ordinary user messages

This is the most important product gap.

The code proves two things:

- `confirmation-bridge` only handles `/confirm`, `/submit`, and `/cancel`; it does not parse normal “create issue” intent. Evidence: `workspace_assets/hooks/confirmation-bridge/handler.ts:115-130`.
- Initial routing into create/close/comment behavior still depends on the model reading `AGENTS.md` and `github-issue-tool/SKILL.md`. Evidence: `.openclaw-feishu-gitissue-gpt54/workspace-larkbot/AGENTS.md:13-22` and `workspace_assets/skills/github-issue-tool/SKILL.md:9-15`.

This means there is no code-level deterministic router for initial issue intent.
If the user explicitly says “create issue” or gives a very issue-shaped request,
the model usually takes the right path. If the wording is vague, the bot may not
switch into the issue workflow at all, and there is no dedicated fallback prompt
that says “I am an issue bot, please specify create/close/comment on an issue”.

This is not just a user-education problem. It is a structural property of the current implementation.

### 5.2 There is still no inbound GitHub event pipeline

Today the repo can send writes to GitHub, but it cannot be awakened by GitHub.
Therefore the future target flow “coding bot comments `/submit` and the issue bot
auto-closes the issue” is still not implemented here.

Evidence:

- `example/example_feishuGitIssue/README.md:5-16`
- `example/example_feishuGitIssue/README.md:37-40`

### 5.3 Pending actions currently cover only create and close

`pending_action.mjs` supports only two kinds:

- `github_issue_create`
- `github_issue_close`

Evidence: `workspace_assets/tools/pending_action.mjs:122-128`.

This is intentional for the `/run` use case, but it also means comments do not
have the same confirmation safety model as create and close.

### 5.4 GitHub tokens are fetched per execution, with no installation-token cache

Evidence:

- `workspace_assets/tools/lib/github_app.mjs:177-219`

There is no persistent installation-token cache in the repo. This is correct but
not optimized. It increases auth exchange frequency and reduces observability.

### 5.5 `/confirm` silently does nothing if no pending action exists

Evidence:

- `workspace_assets/hooks/confirmation-bridge/handler.ts:148-152`

This helps avoid noisy interruptions in normal chat, but from the user side it
looks like the bot ignored the command. It is a real UX gap for debugging.

## 6. One-sentence architectural summary

This is not a fully code-routed GitHub Issue gateway.
It is a specialized OpenClaw workspace that uses local GitHub App-backed tools
to make part of the GitHub Issue workflow reliable enough for create, close,
and explicit comments.

That design gives fast iteration and high reuse of OpenClaw, but it also means
initial intent classification remains model-driven instead of fully deterministic.

## 7. Recommended next steps for the next maintainer

Priority order:

1. Add a code-level intent router or at least a fallback prompt for vague issue requests.
2. Add an inbound GitHub event path, either webhook or poller, for `/submit` and similar follow-up actions.
3. Decide whether issue comments should also enter the pending/confirm model.
4. Add installation-token caching, retry policy, and better runtime observability.

If only one improvement can be made first, do item 1. It directly determines
whether users feel they are talking to an issue bot or to a generic chat bot.