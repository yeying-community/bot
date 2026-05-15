---
name: confirmation-loop
description: |
  Use for preview -> confirm -> execute flows in Feishu/OpenClaw, especially for GitHub Issue creation, updating, and closing that must wait for /confirm, /submit, or /cancel.
---

# Confirmation Loop

Use this skill when the task involves:

- 保存待确认动作
- 展示确认草案
- 等待 `/confirm`
- 等待 `/submit`
- 等待 `/cancel`
- 在多仓库并发草案下做仓库维度确认

## Tool

```bash
node tools/pending_action.mjs --action ...
```

## Rules

- Preview first, execute later.
- Saving a pending action is part of the preview flow.
- Real external write must not happen before explicit confirmation.
- Pending isolation is `same Feishu conversation + same requester + same repository`.
- New preview should replace old pending data only inside that same slot.
- If one requester has multiple repo drafts in the same group, require `/confirm <repo>` or `/cancel <repo>`.
- Confirmation is handled by the hook `hooks/confirmation-bridge`.
