#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

// 解析 `--key value` 风格参数；没有 value 的 flag 统一视为 true。
export function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = "true";
      continue;
    }
    args[key] = next;
    index += 1;
  }
  return args;
}

// 统一处理 CLI 必填参数，缺失时直接抛错。
export function required(name, value) {
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required argument: ${name}`);
  }
  return value;
}

// 把 `a,b,c` 这类参数转成去空白后的字符串数组。
export function parseCsv(value) {
  if (!value) {
    return [];
  }
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

// tool 脚本位于 workspace/tools，下一级目录就是运行 workspace 根目录。
export function workspaceRootFromTool(importMetaUrl) {
  return path.resolve(path.dirname(fileURLToPath(importMetaUrl)), "..");
}

// hook 位于 workspace/hooks/<name>，因此需要多退一级。
export function workspaceRootFromHook(importMetaUrl) {
  return path.resolve(path.dirname(fileURLToPath(importMetaUrl)), "../..");
}

// 只在文件存在时读取 JSON，方便给调用方提供回退值。
export function readJsonIfExists(filePath, fallback = null) {
  if (!fs.existsSync(filePath)) {
    return fallback;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

// 优先读真实 policy；没有时再退回示例文件，确保本地开发也能跑通。
export function loadPolicy(workspaceRoot) {
  const primary = path.join(workspaceRoot, "config", "policy.json");
  const fallback = path.join(workspaceRoot, "config", "policy.example.json");
  if (fs.existsSync(primary)) {
    return readJsonIfExists(primary, {});
  }
  return readJsonIfExists(fallback, {}) || {};
}

// JWT 和文件名都要用安全字符集，所以统一转成 base64url。
export function base64UrlEncode(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

// 飞书消息里经常带 `<at>` 标记，先剥掉再做命令匹配。
export function normalizeText(value) {
  return String(value || "")
    .replace(/<at\b[^>]*>.*?<\/at>/gis, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// 运行在 openclaw 内时优先读取当前实例的 state；否则回退到默认 home 目录。
export function currentSessionsIndexPath() {
  if (process.env.OPENCLAW_STATE_DIR) {
    return path.join(process.env.OPENCLAW_STATE_DIR, "agents", "main", "sessions", "sessions.json");
  }
  return path.join(os.homedir(), ".openclaw", "agents", "main", "sessions", "sessions.json");
}

// 会话索引按更新时间降序排列，取最新一条即可。
export function pickLatestSessionEntry(indexPayload) {
  const entries = Object.entries(indexPayload || {}).sort(
    (left, right) => (right[1]?.updatedAt ?? 0) - (left[1]?.updatedAt ?? 0)
  );
  return entries.length > 0 ? { sessionKey: entries[0][0], entry: entries[0][1] } : null;
}

function extractJsonBlock(text, label) {
  // 元数据会以内嵌 json fenced block 的形式落在用户消息里。
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`${escaped}[\\s\\S]*?\\\`\\\`\\\`json\\s*([\\s\\S]*?)\\\`\\\`\\\``, "i");
  const match = String(text || "").match(pattern);
  if (!match) {
    return null;
  }
  try {
    return JSON.parse(match[1]);
  } catch {
    return null;
  }
}

export function inferConversationContextFromLatestSession() {
  const sessionsIndexPath = currentSessionsIndexPath();
  if (!fs.existsSync(sessionsIndexPath)) {
    return null;
  }

  const indexPayload = JSON.parse(fs.readFileSync(sessionsIndexPath, "utf8"));
  const latest = pickLatestSessionEntry(indexPayload);
  if (!latest?.entry?.sessionFile || !fs.existsSync(latest.entry.sessionFile)) {
    return null;
  }

  const lines = fs
    .readFileSync(latest.entry.sessionFile, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  // 倒序扫描，拿最后一条带会话元数据的用户消息，最符合“当前上下文”。
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    let parsed;
    try {
      parsed = JSON.parse(lines[index]);
    } catch {
      continue;
    }

    if (parsed?.type !== "message" || parsed?.message?.role !== "user") {
      continue;
    }

    const contentItems = Array.isArray(parsed.message.content) ? parsed.message.content : [];
    const combinedText = contentItems
      .filter((item) => item?.type === "text")
      .map((item) => item.text || "")
      .join("\n");

    // 这两段标签来自桥接层附带的非可信元数据，仅用于推断会话范围。
    const conversation = extractJsonBlock(combinedText, "Conversation info (untrusted metadata):");
    const sender = extractJsonBlock(combinedText, "Sender (untrusted metadata):");

    if (!conversation && !sender) {
      continue;
    }

    return {
      sessionKey: latest.sessionKey,
      sessionFile: latest.entry.sessionFile,
      conversation,
      sender
    };
  }

  return null;
}

// 所有工具统一输出结构化 JSON，便于 hook 和上层脚本消费。
export function printJson(payload) {
  console.log(JSON.stringify(payload, null, 2));
}
