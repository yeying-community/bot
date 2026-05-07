#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

import {
  base64UrlEncode,
  inferConversationContextFromLatestSession,
  parseArgs,
  printJson,
  required,
  workspaceRootFromTool
} from "./lib/common.mjs";

// 统一从工具脚本位置回溯到运行 workspace 根目录。
function workspaceRoot() {
  return workspaceRootFromTool(import.meta.url);
}

// 每个会话的待执行动作都落成一个 JSON 文件，便于 hook 和工具共享状态。
function stateDir() {
  const dir = path.join(workspaceRoot(), "state", "pending-actions");
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function inferScopeAndRequester() {
  // 当工具运行在 openclaw 会话内时，优先从最近会话记录反推当前聊天上下文。
  const inferred = inferConversationContextFromLatestSession();
  if (!inferred) {
    return null;
  }

  const conversation = inferred.conversation || {};
  const sender = inferred.sender || {};

  return {
    scope: {
      channelId: "feishu",
      accountId: "default",
      conversationId: conversation.chat_id || conversation.conversation_label || null,
      chatType: conversation.is_group_chat ? "group" : "direct",
      sessionKey: inferred.sessionKey || null,
      sessionFile: inferred.sessionFile || null
    },
    requester: {
      id: sender.id || sender.label || conversation.sender_id || conversation.sender || null,
      label: sender.name || sender.label || conversation.sender_id || conversation.sender || null
    }
  };
}

function currentScopeFromArgsOrEnv(args) {
  // 显式参数优先，其次读 hook 注入的环境变量，最后才回退到会话推断。
  const explicit = {
    channelId: args.channelId || process.env.PENDING_SCOPE_CHANNEL_ID || "feishu",
    accountId: args.accountId || process.env.PENDING_SCOPE_ACCOUNT_ID || "default",
    conversationId: args.conversationId || process.env.PENDING_SCOPE_CONVERSATION_ID || "",
    chatType: args.chatType || process.env.PENDING_SCOPE_CHAT_TYPE || "group"
  };

  if (explicit.conversationId) {
    return explicit;
  }

  const inferred = inferScopeAndRequester();
  if (inferred?.scope?.conversationId) {
    return inferred.scope;
  }

  throw new Error(
    "Unable to resolve current conversation scope. Provide --conversationId or run inside an OpenClaw Feishu session."
  );
}

function currentRequester(args) {
  // 请求人信息只用于权限控制和提示，因此允许缺失。
  if (args.requesterId || args.requesterLabel) {
    return {
      id: args.requesterId || null,
      label: args.requesterLabel || null
    };
  }

  const inferred = inferScopeAndRequester();
  if (inferred?.requester?.id || inferred?.requester?.label) {
    return inferred.requester;
  }

  return null;
}

function scopeFilePath(scope) {
  // 用 base64url 编码 scope，避免 chat id 里的特殊字符污染文件名。
  const key = `${scope.channelId}:${scope.accountId}:${scope.conversationId}`;
  return path.join(stateDir(), `${base64UrlEncode(key)}.json`);
}

function readPending(scope) {
  const filePath = scopeFilePath(scope);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writePending(scope, payload) {
  const filePath = scopeFilePath(scope);
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2));
  return filePath;
}

function clearPending(scope) {
  const filePath = scopeFilePath(scope);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
  return filePath;
}

function buildExecCommand(kind, params) {
  const toolsDir = path.join(workspaceRoot(), "tools");
  // 待确认动作和实际执行脚本之间用 kind 做一层稳定映射。
  const toolByKind = {
    github_issue_create: "github_issue_create.mjs",
    github_issue_close: "github_issue_close.mjs"
  };

  const toolName = toolByKind[kind];
  if (!toolName) {
    throw new Error(`Unsupported pending action kind: ${kind}`);
  }

  const command = [path.join(toolsDir, toolName)];
  for (const [key, value] of Object.entries(params || {})) {
    if (value === undefined || value === null || value === "") {
      continue;
    }
    // 数组参数回写为逗号分隔字符串，和 parseCsv 的输入约定保持一致。
    const normalizedValue = Array.isArray(value) ? value.join(",") : String(value);
    command.push(`--${key}`, normalizedValue);
  }
  command.push("--execute");
  return command;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const action = args.action || "get";
  const scope = currentScopeFromArgsOrEnv(args);

  if (action === "create") {
    // create 只把预览信息和执行参数持久化，不产生外部副作用。
    const kind = required("kind", args.kind);
    const headline = required("headline", args.headline);
    const paramsJson = required("paramsJson", args.paramsJson);
    const previewNote = args.previewNote || "";
    const requester = currentRequester(args);
    const payload = {
      version: 1,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      scope,
      kind,
      headline,
      previewNote,
      params: JSON.parse(paramsJson),
      ...(requester ? { requester } : {})
    };
    const filePath = writePending(scope, payload);
    printJson({
      ok: true,
      action,
      filePath,
      pending: payload
    });
    return;
  }

  if (action === "get") {
    // 未找到待执行动作时返回非零退出码，方便 hook 直接短路。
    const pending = readPending(scope);
    printJson({
      ok: Boolean(pending),
      action,
      scope,
      pending
    });
    process.exit(pending ? 0 : 1);
  }

  if (action === "clear") {
    const filePath = clearPending(scope);
    printJson({
      ok: true,
      action,
      scope,
      filePath
    });
    return;
  }

  if (action === "execute") {
    const pending = readPending(scope);
    if (!pending) {
      printJson({
        ok: false,
        action,
        scope,
        error: "No pending action for current conversation."
      });
      process.exit(1);
    }

    const command = buildExecCommand(pending.kind, pending.params);
    const result = spawnSync(process.execPath, command, {
      env: process.env,
      encoding: "utf8"
    });
    const raw = (result.stdout || result.stderr || "").trim();
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = { raw };
    }

    if (result.status === 0 && parsed?.ok) {
      // 只有真正执行成功才删除 pending，失败时保留给用户重试或取消。
      clearPending(scope);
      printJson({
        ok: true,
        action,
        scope,
        executed: parsed
      });
      return;
    }

    printJson({
      ok: false,
      action,
      scope,
      executed: parsed
    });
    process.exit(1);
  }

  if (action === "list") {
    // list 主要给排障或后台巡检使用，直接枚举整个目录。
    const entries = fs
      .readdirSync(stateDir())
      .filter((name) => name.endsWith(".json"))
      .map((name) => JSON.parse(fs.readFileSync(path.join(stateDir(), name), "utf8")));
    printJson({
      ok: true,
      action,
      entries
    });
    return;
  }

  throw new Error(`Unsupported action: ${action}`);
}

main();
