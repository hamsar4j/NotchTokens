# AGENTS.md

This file provides guidance to Codex and other coding agents when working with code in this repository.

## Build & run

```bash
# Build (debug)
xcodebuild -scheme NotchTokens -configuration Debug -destination 'platform=macOS' build

# Clean build
xcodebuild -scheme NotchTokens -configuration Debug -destination 'platform=macOS' clean build

# Run: open the built .app from DerivedData, or hit Cmd-R in Xcode
```

There are no tests, no linter, no Swift Package — just the Xcode project. The target is a macOS menubar (`.accessory`) app.

The project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup`: any file added under `NotchTokens/` (including subdirectories) is automatically included in the target. No `.pbxproj` edits are needed when adding/moving Swift files, assets, or resources — moving a `.swift` file with `mv` into a new subdir works after a clean build.

After edits, ignore SourceKit "Cannot find type / member" warnings — they appear because Xcode's index has not caught up. The `xcodebuild` command is the source of truth.

## Commit & Pull Request Guidelines

Use only these Conventional Commit prefixes: `feat:`, `fix:`, and `chore:`. Keep commit subjects short and imperative, for example `fix: guard stale /model callback`.

When a coding phase is completed, always suggest a commit message in the final handoff. Prefer a single Conventional Commit-style subject line that matches the completed change set.

## Architecture

This is a notch-anchored AppKit panel that tracks token usage and cost for three AI coding harnesses: Claude Code, OpenAI Codex CLI, and OpenCode. The data flow:

```text
UsageMonitor (timer, 60s)
  ├── PricingFetcher (actor)
  ├── ClaudeUsageService (actor, OAuth API)
  └── LocalUsageReader (struct, JSONL/JSON files)
      └── UsageSnapshot -> NotchUsagePanelView (NSView)
```

## Provider data

- **Claude Code**: token totals + cost come from per-message JSONL records under `~/.claude/projects/**/*.jsonl`. Dedupe key is `requestId-messageId` because retries can write duplicate usage rows. Live 5h / 7-day limit percentages come from Anthropic's undocumented `https://api.anthropic.com/api/oauth/usage` endpoint via `ClaudeUsageService`; auth token is read from the `Claude Code-credentials` Keychain entry via `/usr/bin/security` or `$CLAUDE_CODE_OAUTH_TOKEN`. Failures back off exponentially: 60 -> 600s, or 120 -> 600s for 401/403.
- **Codex**: token totals + cost come from `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/**/*.jsonl`. Codex emits cumulative `total_token_usage` in `token_count` events, so take the last one per session, not a sum. Rate limits are pulled from `rate_limits` blocks on those events. Codex model name is read from `~/.codex/config.toml` when not present in JSONL. Codex `input_tokens` includes cached tokens, so subtract `cached_input_tokens` before pricing to avoid double-charging.
- **OpenCode**: message data comes from `~/.local/share/opencode/storage/message/<session>/<msg>.json`. Each message already has a pre-computed `cost` field plus structured `tokens.{input,output,reasoning,cache.{read,write}}`, so sum those directly. OpenCode has no native rate-limit concept; budget bars are synthetic.

## Pricing

`PricingFetcher` loads a `PricingTable` decoded from LiteLLM's `model_prices_and_context_window.json`. Sources are tried in this order:

1. Disk cache: `~/Library/Caches/NotchTokens/pricing.json` with a 24h TTL.
2. Bundled fallback: `Resources/pricing-fallback.json`.
3. Network: `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` only when stale.

`PricingTable.rate(for:)` tries exact match, then strips date suffixes, then strips vendor prefixes, then tries prefix match. Unknown models return `nil`; their cost contribution is `0`, not an error.

OpenCode does not consult this table because it has its own per-message cost field.

## UI structure

- `NotchPanelController` owns an `NSPanel` with `.borderless`, `.nonactivatingPanel`, and `.fullSizeContentView`, at `.statusBar` level. The `.nonactivatingPanel` mask is load-bearing.
- `NotchUsagePanelView` is one hand-drawn `NSView` with collapsed pill and expanded panel layouts. Hover expansion is animated via `NSAnimationContext`; `setFrameSize` triggers redraws during animation.
- Hover flicker is suppressed by a debounced collapse that checks `NSEvent.mouseLocation` against the window frame before collapsing.
- The view is `isFlipped = true`, so image drawing must use `respectFlipped: true` or assets render upside down.

## Settings and budget limits

User settings live in `~/Library/Application Support/NotchTokens/config.json`, persisted via `SettingsStore`.

Codex and OpenCode budgets use a rolling 30-day dollar window. `LocalUsageReader` sums cost from the last 30 days, and `UsageMonitor.refresh()` appends a synthetic `LimitWindow(name: "30d", usedPercent: rollingCost / budget * 100, resetsAt: nil)` for any provider with a budget. The panel renders this synthetic window the same way it renders real provider limits.

Claude Code does not use a user budget. It uses live provider limit windows returned by Anthropic.

## Adding a new harness

Pattern: add a `ProviderKind` case, add a placeholder in `UsageSnapshot.placeholder`, add a `read<Name>()` method on `LocalUsageReader` or a separate service, add an asset in `Assets.xcassets/<name>.imageset`, then wire `drawProviderLogo`, the collapsed-segment list, and the expanded-row loop in `NotchUsagePanelView`. The expanded panel size and collapsed pill width may need to grow to fit more rows/segments.
