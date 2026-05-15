#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

import { inferInboundAttachmentsFromLatestSession } from "./common.mjs";
import { githubApiJson } from "./github_app.mjs";

const ISSUE_ATTACHMENT_MARKER = "<!-- issuer-attachments -->";
const DEFAULT_MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

function slugifyFilename(filename) {
  return String(filename || "attachment")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "") || "attachment";
}

function buildUploadPath(filename) {
  const date = new Date();
  const yyyy = String(date.getUTCFullYear());
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  return `issuer-attachments/${yyyy}/${mm}/${dd}/${stamp}-${slugifyFilename(filename)}`;
}

function attachmentMarkdown(entry, repoIsPrivate) {
  if (entry.status !== "uploaded") {
    return `- ${entry.filename} (${entry.mimeType || "unknown"})：上传失败，原因：${entry.error}`;
  }

  if (!repoIsPrivate && entry.downloadUrl && entry.mimeType?.startsWith("image/")) {
    return `- ${entry.filename} (${entry.mimeType})：[查看文件](${entry.htmlUrl})\n\n![${entry.filename}](${entry.downloadUrl})`;
  }

  return `- ${entry.filename} (${entry.mimeType || "unknown"})：[查看文件](${entry.htmlUrl})`;
}

function appendUploadedAttachmentSection(body, attachments, repoIsPrivate) {
  const originalBody = String(body || "");
  if (attachments.length === 0 || originalBody.includes(ISSUE_ATTACHMENT_MARKER)) {
    return originalBody;
  }

  const section = [
    ISSUE_ATTACHMENT_MARKER,
    "## 附件",
    repoIsPrivate
      ? "以下附件已上传到目标仓库，可通过仓库链接查看："
      : "以下附件已上传到目标仓库：",
    ...attachments.map((item) => attachmentMarkdown(item, repoIsPrivate))
  ].join("\n");

  return `${originalBody.trimEnd()}\n\n${section}\n`;
}

async function repositoryMeta(owner, repo, token) {
  return githubApiJson(`https://api.github.com/repos/${owner}/${repo}`, { token });
}

async function uploadAttachment({ owner, repo, token, branch, attachment, maxUploadBytes }) {
  const localPath = String(attachment?.localPath || "").trim();
  const filename = attachment?.filename || path.basename(localPath) || "attachment";
  const mimeType = attachment?.mimeType || "application/octet-stream";

  if (!localPath || !fs.existsSync(localPath)) {
    return {
      status: "failed",
      filename,
      mimeType,
      error: "local file not found"
    };
  }

  const stat = fs.statSync(localPath);
  if (!stat.isFile()) {
    return {
      status: "failed",
      filename,
      mimeType,
      error: "local path is not a file"
    };
  }

  if (stat.size > maxUploadBytes) {
    return {
      status: "failed",
      filename,
      mimeType,
      error: `file too large (${stat.size} bytes > ${maxUploadBytes} bytes)`
    };
  }

  const repoPath = buildUploadPath(filename);
  const content = fs.readFileSync(localPath).toString("base64");
  const payload = await githubApiJson(
    `https://api.github.com/repos/${owner}/${repo}/contents/${repoPath.split("/").map(encodeURIComponent).join("/")}`,
    {
      method: "PUT",
      token,
      body: {
        message: `issuer: upload attachment ${filename}`,
        content,
        branch
      }
    }
  );

  return {
    status: "uploaded",
    filename,
    mimeType,
    size: stat.size,
    localPath,
    repoPath,
    branch,
    htmlUrl: payload?.content?.html_url || `https://github.com/${owner}/${repo}/blob/${branch}/${repoPath}`,
    downloadUrl:
      payload?.content?.download_url ||
      `https://raw.githubusercontent.com/${owner}/${repo}/${encodeURIComponent(branch).replace(/%2F/g, "/")}/${repoPath
        .split("/")
        .map(encodeURIComponent)
        .join("/")}`
  };
}

export async function enrichTextWithUploadedAttachments({ owner, repo, auth, body }) {
  const attachments = inferInboundAttachmentsFromLatestSession();
  if (attachments.length === 0) {
    return {
      body,
      attachments: [],
      repository: null
    };
  }

  const repoMeta = await repositoryMeta(owner, repo, auth.token);
  const maxUploadBytes = Number(process.env.GITHUB_ATTACHMENT_MAX_BYTES || DEFAULT_MAX_UPLOAD_BYTES);
  const uploaded = [];

  for (const attachment of attachments) {
    try {
      uploaded.push(
        await uploadAttachment({
          owner,
          repo,
          token: auth.token,
          branch: repoMeta.default_branch || "main",
          attachment,
          maxUploadBytes
        })
      );
    } catch (error) {
      uploaded.push({
        status: "failed",
        filename: attachment?.filename || "attachment",
        mimeType: attachment?.mimeType || "application/octet-stream",
        localPath: attachment?.localPath || "",
        error: error instanceof Error ? error.message : String(error)
      });
    }
  }

  return {
    repository: {
      defaultBranch: repoMeta.default_branch || "main",
      private: !!repoMeta.private
    },
    attachments: uploaded,
    body: appendUploadedAttachmentSection(body, uploaded, !!repoMeta.private)
  };
}
