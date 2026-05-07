import { spawnSync } from "node:child_process";
import path from "node:path";

import { loadPolicy, normalizeText, workspaceRootFromHook } from "../../tools/lib/common.mjs";

// hook 运行时所在目录固定，因此可以稳定定位到 workspace/tools。
function toolsDir() {
  return path.join(workspaceRootFromHook(import.meta.url), "tools");
}

// 通过子进程复用现有工具，并把当前会话范围传给 pending_action。
function runTool(toolName, args, scope) {
  return spawnSync(process.execPath, [path.join(toolsDir(), toolName), ...args], {
    env: {
      ...process.env,
      PENDING_SCOPE_CHANNEL_ID: scope.channelId || "feishu",
      PENDING_SCOPE_ACCOUNT_ID: scope.accountId || "default",
      PENDING_SCOPE_CONVERSATION_ID: scope.conversationId || "",
      PENDING_SCOPE_CHAT_TYPE: scope.chatType || "group"
    },
    encoding: "utf8"
  });
}

// 工具默认输出 JSON；解析失败时也保留原始文本，方便给用户兜底提示。
function parseJsonOutput(result) {
  const raw = (result.stdout || result.stderr || "").trim();
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return { raw };
  }
}

// 只拦截飞书收消息事件，避免对其他平台或事件类型误触发。
function isFeishuMessageEvent(event) {
  return event?.type === "message" && event?.action === "received" && event?.context?.channelId === "feishu";
}

// 从桥接层附加的 metadata 里尽量还原操作者身份。
function resolveSender(event) {
  return {
    id: event?.context?.metadata?.senderId || event?.context?.from || null,
    label:
      event?.context?.metadata?.senderName ||
      event?.context?.metadata?.senderUsername ||
      event?.context?.metadata?.senderId ||
      event?.context?.from ||
      null
  };
}

// policy 未自定义时使用内置确认命令集合。
function confirmCommands(policy) {
  return Array.isArray(policy?.confirmCommands) && policy.confirmCommands.length > 0
    ? policy.confirmCommands
    : ["/confirm", "/submit", "确认", "确认一下", "创建 issue", "创建 github issue", "提交", "提交 issue", "提交 github issue"];
}

// 取消命令同理，允许管理员或发起人中断待执行操作。
function cancelCommands(policy) {
  return Array.isArray(policy?.cancelCommands) && policy.cancelCommands.length > 0
    ? policy.cancelCommands
    : ["/cancel", "取消", "算了", "不用了", "先别创建"];
}

// 统一归一化文本后做包含匹配，兼容“确认一下”“提交 issue”这类自然语言。
function matchesCommand(text, candidates) {
  const normalized = normalizeText(text).toLowerCase();
  return candidates.some((candidate) => normalized.includes(String(candidate).toLowerCase()));
}

// 默认只允许原始请求人确认；policy.admins 可以作为兜底管理员白名单。
function isAllowedConfirmer(policy, pending, sender) {
  if (!sender?.id) {
    return {
      allowed: false,
      reason: "无法识别确认人，请让发起人本人或管理员发送命令。"
    };
  }

  if (pending?.requester?.id && sender.id === pending.requester.id) {
    return { allowed: true };
  }

  const admins = Array.isArray(policy?.admins) ? policy.admins : [];
  if (admins.includes(sender.id)) {
    return { allowed: true };
  }

  return {
    allowed: false,
    reason: "只有发起人本人或管理员可以确认或取消当前操作。"
  };
}

// 成功提示尽量带上 issue 编号和链接，方便用户直接跳转。
function successMessage(kind, issue) {
  if (!issue?.htmlUrl) {
    return kind === "github_issue_close" ? "已关闭 GitHub Issue。" : "已创建 GitHub Issue。";
  }

  if (kind === "github_issue_close" || issue?.state === "closed") {
    return `已关闭 GitHub Issue #${issue.number} ${issue.title}
${issue.htmlUrl}`;
  }

  return `已创建 GitHub Issue #${issue.number} ${issue.title}
${issue.htmlUrl}`;
}

const handler = async (event) => {
  if (!isFeishuMessageEvent(event)) {
    return;
  }

  const workspaceRoot = workspaceRootFromHook(import.meta.url);
  const policy = loadPolicy(workspaceRoot);
  const text = normalizeText(event?.context?.content || "");
  if (!text) {
    return;
  }

  const isConfirm = matchesCommand(text, confirmCommands(policy));
  const isCancel = matchesCommand(text, cancelCommands(policy));
  if (!isConfirm && !isCancel) {
    return;
  }

  // pending action 以“会话”为粒度隔离，所以 scope 必须稳定且可复现。
  const scope = {
    channelId: "feishu",
    accountId: event?.context?.accountId || "default",
    conversationId: event?.context?.conversationId || event?.context?.metadata?.to || event?.context?.to || "",
    chatType: event?.context?.conversationId ? "group" : "direct"
  };

  if (!scope.conversationId) {
    if (Array.isArray(event.messages)) {
      event.messages.push("无法定位当前会话，不能处理确认命令。");
    }
    return;
  }

  // 当前会话没有待确认动作时静默返回，不打断正常聊天。
  const pending = parseJsonOutput(runTool("pending_action.mjs", ["--action", "get"], scope));
  if (!pending?.ok || !pending?.pending) {
    return;
  }

  const sender = resolveSender(event);
  const allowed = isAllowedConfirmer(policy, pending.pending, sender);
  if (!allowed.allowed) {
    if (Array.isArray(event.messages)) {
      event.messages.push(allowed.reason || "只有发起人本人或管理员可以确认或取消当前操作。");
    }
    return;
  }

  if (isCancel) {
    // 取消动作只清状态，不执行任何外部副作用。
    runTool("pending_action.mjs", ["--action", "clear"], scope);
    if (Array.isArray(event.messages)) {
      event.messages.push("已取消待执行操作。");
    }
    return;
  }

  // 真正执行 GitHub 动作前，再次通过 pending_action 做一次统一分发。
  const executed = parseJsonOutput(runTool("pending_action.mjs", ["--action", "execute"], scope));
  if (!executed?.ok) {
    if (Array.isArray(event.messages)) {
      const failure =
        executed?.executed?.response?.message ||
        executed?.executed?.error ||
        executed?.error ||
        "执行失败，请检查 GitHub 配置或最近日志，必要时重新发起或先发送 /cancel。";
      event.messages.push(`执行失败：${failure}`);
    }
    return;
  }

  const issue = executed?.executed?.result;
  const kind = pending.pending.kind;
  if (Array.isArray(event.messages)) {
    event.messages.push(successMessage(kind, issue));
  }
};

export default handler;
