# Standalone Feishu OpenClaw (Repo Copy)

This directory is a standalone, repository-friendly copy of the Feishu OpenClaw instance.

## Included
- `workspace-larkbot/` prompt/persona/workspace files
- `config/openclaw.json.template` sanitized template (no real secrets)
- `start_lark_atonly_g53.sh`, `stop_lark_atonly_g53.sh`, `status_lark_atonly_g53.sh`

## Excluded From Git
- Runtime/history/state files: `state/`, `gateway.out`, `openclaw.pid`
- Secret configs: `config/openclaw.json`, credential markdowns
- Nested runtime/git metadata under workspace

## First-time Setup
1. `cp config/openclaw.json.template config/openclaw.json`
2. Fill real values:
   - `models.providers.router.apiKey`
   - `channels.feishu.appId`
   - `channels.feishu.appSecret`
   - `channels.feishu.groupAllowFrom`
   - `channels.feishu.groups`
   - `gateway.auth.token`
3. Start: `./start_lark_atonly_g53.sh`
