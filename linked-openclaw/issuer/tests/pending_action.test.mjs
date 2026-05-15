import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { appRoot, makeTempDir, readJsonLines, runNodeJson, writeJson } from "./helpers.mjs";

const pendingActionPath = path.join(appRoot, "workspace_assets", "tools", "pending_action.mjs");

function testEnv(root) {
  return {
    PENDING_DB_PATH: path.join(root, "state", "pending-actions.sqlite3"),
    PENDING_STATE_DIR: path.join(root, "legacy-pending-actions"),
    ISSUER_AUDIT_LOG_PATH: path.join(root, "logs", "issuer-audit.jsonl")
  };
}

function createDraft(env, options) {
  return runNodeJson(
    pendingActionPath,
    [
      "--action",
      "create",
      "--conversationId",
      options.conversationId,
      "--requesterId",
      options.requesterId,
      "--requesterLabel",
      options.requesterLabel,
      "--kind",
      options.kind || "github_issue_create",
      "--headline",
      options.headline,
      "--paramsJson",
      JSON.stringify(options.params)
    ],
    { env }
  );
}

test("pending_action keeps repo-scoped drafts isolated in sqlite", () => {
  const root = makeTempDir("issuer-pending-");
  const env = testEnv(root);

  const first = createDraft(env, {
    conversationId: "chat-a",
    requesterId: "user-a",
    requesterLabel: "UserA",
    headline: "robot draft",
    params: {
      owner: "yeying-community",
      repo: "robot",
      title: "T1",
      body: "B1"
    }
  });
  assert.equal(first.result.status, 0);
  assert.equal(first.json.ok, true);

  const second = createDraft(env, {
    conversationId: "chat-a",
    requesterId: "user-a",
    requesterLabel: "UserA",
    headline: "openclaw draft",
    params: {
      owner: "yeying-community",
      repo: "openclaw",
      title: "T2",
      body: "B2"
    }
  });
  assert.equal(second.result.status, 0);
  assert.equal(second.json.ok, true);
  const openclawDraftId = second.json.pending.draftId;

  const ambiguous = runNodeJson(
    pendingActionPath,
    ["--action", "get", "--conversationId", "chat-a", "--requesterId", "user-a"],
    { env }
  );
  assert.equal(ambiguous.result.status, 1);
  assert.equal(ambiguous.json.error, "ambiguous");

  const robotGet = runNodeJson(
    pendingActionPath,
    ["--action", "get", "--conversationId", "chat-a", "--requesterId", "user-a", "--repoQuery", "robot"],
    { env }
  );
  assert.equal(robotGet.result.status, 0);
  assert.equal(robotGet.json.pending.target.repo, "robot");
  const originalDraftId = robotGet.json.pending.draftId;

  const openclawByDraft = runNodeJson(
    pendingActionPath,
    ["--action", "get", "--conversationId", "chat-a", "--requesterId", "user-a", "--draftQuery", openclawDraftId.slice(0, 8)],
    { env }
  );
  assert.equal(openclawByDraft.result.status, 0);
  assert.equal(openclawByDraft.json.pending.target.repo, "openclaw");

  const overwrite = createDraft(env, {
    conversationId: "chat-a",
    requesterId: "user-a",
    requesterLabel: "UserA",
    headline: "robot overwrite",
    params: {
      owner: "yeying-community",
      repo: "robot",
      title: "T1b",
      body: "B1b"
    }
  });
  assert.equal(overwrite.result.status, 0);
  assert.equal(overwrite.json.pending.headline, "robot overwrite");
  assert.notEqual(overwrite.json.pending.draftId, originalDraftId);

  const otherUser = createDraft(env, {
    conversationId: "chat-a",
    requesterId: "user-b",
    requesterLabel: "UserB",
    headline: "robot other user",
    params: {
      owner: "yeying-community",
      repo: "robot",
      title: "T3",
      body: "B3"
    }
  });
  assert.equal(otherUser.result.status, 0);
  assert.equal(otherUser.json.sameRepoOtherRequesters.length, 1);
  assert.equal(otherUser.json.sameRepoOtherRequesters[0].requester.id, "user-a");

  const list = runNodeJson(
    pendingActionPath,
    ["--action", "list", "--conversationId", "chat-a", "--requesterId", "user-a"],
    { env }
  );
  assert.equal(list.result.status, 0);
  assert.equal(list.json.entries.length, 2);
  assert.deepEqual(
    list.json.entries.map((entry) => entry.target.repo).sort(),
    ["openclaw", "robot"]
  );

  const cleared = runNodeJson(
    pendingActionPath,
    ["--action", "clear", "--conversationId", "chat-a", "--requesterId", "user-a", "--repoQuery", "robot"],
    { env }
  );
  assert.equal(cleared.result.status, 0);
  assert.equal(cleared.json.pending.target.repo, "robot");

  const notFound = runNodeJson(
    pendingActionPath,
    ["--action", "get", "--conversationId", "chat-a", "--requesterId", "user-a", "--repoQuery", "robot"],
    { env }
  );
  assert.equal(notFound.result.status, 1);
  assert.equal(notFound.json.error, "not_found");

  const auditEntries = readJsonLines(env.ISSUER_AUDIT_LOG_PATH).map((entry) => entry.event);
  assert.ok(auditEntries.includes("pending.create"));
  assert.ok(auditEntries.includes("pending.clear"));
});

test("pending_action migrates legacy json drafts into sqlite once", () => {
  const root = makeTempDir("issuer-pending-migrate-");
  const env = testEnv(root);
  const legacyDir = env.PENDING_STATE_DIR;
  fs.mkdirSync(legacyDir, { recursive: true });

  const slotKey = "feishu:default:chat-migrate:user-a:yeying-community/robot";
  writeJson(path.join(legacyDir, "legacy.json"), {
    version: 2,
    createdAt: "2026-05-14T00:00:00.000Z",
    updatedAt: "2026-05-14T00:00:00.000Z",
    scope: {
      channelId: "feishu",
      accountId: "default",
      conversationId: "chat-migrate",
      chatType: "group"
    },
    requester: {
      id: "user-a",
      label: "UserA"
    },
    target: {
      owner: "yeying-community",
      repo: "robot",
      repoKey: "yeying-community/robot",
      issueNumber: null
    },
    slotKey,
    kind: "github_issue_create",
    headline: "legacy draft",
    previewNote: "",
    params: {
      owner: "yeying-community",
      repo: "robot",
      title: "Legacy",
      body: "Legacy body"
    }
  });

  const migrated = runNodeJson(
    pendingActionPath,
    ["--action", "get", "--conversationId", "chat-migrate", "--requesterId", "user-a", "--repoQuery", "robot"],
    { env }
  );
  assert.equal(migrated.result.status, 0);
  assert.equal(migrated.json.pending.headline, "legacy draft");
  assert.ok(fs.existsSync(env.PENDING_DB_PATH));

  const archives = fs
    .readdirSync(root)
    .filter((name) => name.startsWith("legacy-pending-actions.legacy-imported-"));
  assert.equal(archives.length, 1);
  assert.equal(fs.readdirSync(legacyDir).length, 0);
});
