# NotchTokens

A macOS notch app that tracks token usage and cost across **Claude Code**, **OpenAI Codex CLI**, and **OpenCode** at a glance.

Hover the notch to expand a panel with per-harness usage bars (green → yellow → red as you approach rate limits) and live cost totals. Click-pin to keep it open.

## Requirements

- macOS with a notch (M-series MacBook Pro / Air)
- Xcode 16+ to build
- At least one of: Claude Code, Codex CLI, or OpenCode installed and used locally

## Install

```bash
git clone <repo> && cd NotchTokens
open NotchTokens.xcodeproj
# Product → Archive → Distribute App → Custom → Copy App
# Drag NotchTokens.app into /Applications
```

First launch: right-click the app → **Open** → **Open** (Gatekeeper bypass, one time only since the build is locally signed).

To launch at login: **System Settings → General → Login Items → +** → add `NotchTokens.app`.

## How it works

All data is read locally — no scraping, no API keys to paste:

| Harness | Source |
|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` for tokens + cost; `api.anthropic.com/api/oauth/usage` (using the OAuth token from your existing Claude Code Keychain entry) for live 5h / 7-day limits |
| Codex | `~/.codex/sessions/**/*.jsonl` for tokens + cost; embedded `rate_limits` for Short / Long limit windows |
| OpenCode | `~/.local/share/opencode/storage/message/**/*.json` (cost is pre-computed by OpenCode itself) |

Pricing is sourced from [LiteLLM's `model_prices_and_context_window.json`](https://github.com/BerriAI/litellm), refreshed daily, with an embedded snapshot for offline use. OpenCode uses its own per-message cost field instead.

The Claude OAuth token is read via `/usr/bin/security` from the existing `Claude Code-credentials` Keychain entry — you'll get one macOS permission prompt on first run; click "Always Allow." No new credentials needed.

## Acknowledgments

Approach inspired by [ccusage](https://github.com/ryoppippi/ccusage), [Tokscale](https://github.com/junhoyeo/tokscale), [Notchi](https://github.com/sk-ruban/notchi), and [CodexBar](https://github.com/steipete/CodexBar).
