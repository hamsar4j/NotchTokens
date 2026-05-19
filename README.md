# NotchTokens

A macOS notch app that tracks token usage and cost across **Claude Code**, **OpenAI Codex CLI**, and **OpenCode** at a glance.

Hover the notch to expand a panel with per-harness usage bars (green → yellow → red as you approach rate limits) and live cost totals. Click-pin to keep it open, or use the refresh button to reread usage immediately.

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

| Harness | Usage source | Limit source |
|---|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` for tokens + cost | Anthropic's OAuth usage endpoint, using the OAuth token from the existing Claude Code Keychain entry, for live 5h / 7-day limits |
| Codex | `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/**/*.jsonl` for tokens + cost | Embedded `rate_limits` for Short / Long windows when present, plus optional rolling 30-day budget |
| OpenCode | `~/.local/share/opencode/storage/message/**/*.json`; cost is pre-computed by OpenCode itself | Optional rolling 30-day budget |

Pricing is sourced from [LiteLLM's `model_prices_and_context_window.json`](https://github.com/BerriAI/litellm), refreshed daily, with an embedded snapshot for offline use. OpenCode uses its own per-message cost field instead.

Codex and OpenCode budget bars use rolling last-30-day spend. Claude Code uses the live limit windows returned by Anthropic.

The Claude OAuth token is read via `/usr/bin/security` from the existing `Claude Code-credentials` Keychain entry — you'll get one macOS permission prompt on first run; click "Always Allow." No new credentials needed.

## Refresh cadence

- Usage and limit data refresh on launch, every 60 seconds after launch, and whenever you click the refresh button.
- Claude live limits are fetched every refresh unless the Anthropic request fails. Failures use exponential backoff and cached limits are reused while waiting.
- Codex and OpenCode budgets are recalculated from the last 30 days on every refresh.

## Settings

Open the gear button in the panel footer to set Codex and OpenCode budgets. These are local dollar budgets used only to render synthetic 30-day usage bars; Claude Code does not need a budget because it exposes live limit windows.

## Acknowledgments

Approach inspired by [ccusage](https://github.com/ryoppippi/ccusage), [Tokscale](https://github.com/junhoyeo/tokscale), [Notchi](https://github.com/sk-ruban/notchi), and [CodexBar](https://github.com/steipete/CodexBar).
