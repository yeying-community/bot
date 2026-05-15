---
name: confirmation-bridge
description: "Handle /help, /confirm, /submit, and /cancel in Feishu for saved pending GitHub Issue create / update / close actions."
metadata:
  { "openclaw": { "emoji": "✅", "events": ["message:received"], "requires": { "bins": ["node"] } } }
---

# Confirmation Bridge

This hook listens for Feishu help / confirmation messages and turns saved pending actions into real execution.

It should:

- reply help text for `/help` from `help.template.md`
- read pending action for the current Feishu conversation and current requester
- detect `/confirm`, `/submit`, `/cancel`
- support explicit repo confirmation like `/confirm robot`
- support explicit draft confirmation like `/confirm draft:5d496c27`
- allow only requester or admins
- execute GitHub Issue create, update, or close
- reply back into the same Feishu conversation
