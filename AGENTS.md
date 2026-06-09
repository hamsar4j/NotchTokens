# AGENTS.md

This file provides guidance to Claude Code, Codex, and other coding agents when working with code in this repository.

## Build & run

```bash
# Build (debug)
xcodebuild -scheme NotchTokens -configuration Debug -destination 'platform=macOS' build

# Clean build
xcodebuild -scheme NotchTokens -configuration Debug -destination 'platform=macOS' clean build

# Run tests (hosted NotchTokensTests target)
xcodebuild test -scheme NotchTokens -configuration Debug -destination 'platform=macOS'

# Format / lint (Apple swift-format, config in .swift-format)
xcrun swift format format --in-place --recursive --configuration .swift-format NotchTokens NotchTokensTests
xcrun swift format lint --recursive --configuration .swift-format NotchTokens NotchTokensTests

# Run: open the built .app from DerivedData, or hit ⌘R in Xcode
```

There is no Swift Package — just the Xcode project, plus a hosted `NotchTokensTests` unit-test target. The build target is a macOS menubar (`.accessory`) app.

## Formatting, linting & strictness

- **Formatter/linter:** Apple's `swift format` (toolchain subcommand, no extra install), configured by `.swift-format` (4-space indent, 120 col). Formatting is the enforced layer; lint is advisory because some lines (long JSONL test fixtures) legitimately exceed the column limit.
- **Pre-commit hook:** `.githooks/pre-commit` formats staged Swift files in place, re-stages them, and runs an advisory lint. Enable once per clone: `git config core.hooksPath .githooks`.
- **Compiler strictness (Debug only):** the Debug config sets `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` — this is the closest thing to a type checker, so a clean Debug build is the gate. Release is left lenient so archives never break on a new warning. Keep code concurrency-clean (no Sendable-closure mutation of `@MainActor` state; selector-based timers, or `nonisolated(unsafe)` for deinit-touched stored properties).

The project uses **Xcode 16's `PBXFileSystemSynchronizedRootGroup`**: any file added under `NotchTokens/` (including subdirectories) is automatically included in the target. No `.pbxproj` edits are needed when adding/moving Swift files, assets, or resources — moving a `.swift` file with `mv` into a new subdir Just Works after a clean build. (Test files go under `NotchTokensTests/`, which is its own synchronized group.)

After Edits, ignore SourceKit "Cannot find type / member" warnings — they appear because Xcode's index hasn't caught up. The `xcodebuild` command is the source of truth.

## Commit & Pull Request Guidelines

Use only these Conventional Commit prefixes: `feat:`, `fix:`, and `chore:`. Keep commit subjects short and imperative, for example `fix: guard stale /model callback`.

When a coding phase is completed, always suggest a commit message in the final handoff. Prefer a single Conventional Commit-style subject line that matches the completed change set.

## Architecture

This is a notch-anchored AppKit panel that tracks token usage and cost for three AI coding harnesses: **Claude Code**, **OpenAI Codex CLI**, and **OpenCode**. The data flow:

```
UsageMonitor (timer, 60s)
  ├── PricingFetcher (actor) ──┐
  ├── ClaudeUsageService (actor, OAuth API) ──┐
  └── LocalUsageReader (struct, JSONL/JSON files) ──┐
                                                     ▼
                                              UsageSnapshot ──▶ NotchUsagePanelView (NSView)
```

### Where each provider's data comes from

- **Claude Code**: token totals + cost computed from per-message JSONL records under `~/.claude/projects/**/*.jsonl`. Dedupe key is `requestId-messageId` (retries write duplicate usage rows). Live 5h / 7-day limit *percentages* come from Anthropic's undocumented `https://api.anthropic.com/api/oauth/usage` endpoint (`ClaudeUsageService`); auth token is read from the `Claude Code-credentials` Keychain entry via `/usr/bin/security` (the same one the CLI itself uses) or `$CLAUDE_CODE_OAUTH_TOKEN`. Failures back off exponentially (60→600s, 120→600s for 401/403).
- **Codex**: token totals + cost from `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/**/*.jsonl`. Codex emits *cumulative* `total_token_usage` in `token_count` events, so we take the last one per session, not a sum. Rate limits are pulled from any `rate_limits` block present on those events (Short / Long windows). **Codex does not record the model name in JSONL** — it's stored in `~/.codex/config.toml` (top-level `model = "..."`). The reader parses that file once per snapshot and uses it as the model for every session. **Codex's `input_tokens` is OpenAI-style and INCLUDES cached tokens**, so before pricing we subtract `cached_input_tokens` from `input_tokens` to avoid double-charging. Anthropic's `input_tokens` already excludes cache, so the Claude path doesn't do this subtraction.
- **OpenCode**: walks `~/.local/share/opencode/storage/message/<session>/<msg>.json`. Each message file already has a pre-computed `cost` field and a structured `tokens.{input,output,reasoning,cache.{read,write}}` block, so we just sum — no pricing lookup needed. OpenCode has no native rate-limit concept, so its bar stays empty (`limits: []`), which is correct, not a bug.

`LocalUsageReader` takes an optional `baseDirectory` (defaults to the home dir) so it can be pointed at fixture directories in tests. Per-file reads skip anything over 50 MB (`boundedData`) to avoid materializing a pathological multi-GB JSONL into memory.

### Pricing

`PricingFetcher` (actor) loads a `PricingTable` decoded from LiteLLM's `model_prices_and_context_window.json` (~1.4 MB). Sources are tried in this order:

1. Disk cache: `~/Library/Caches/NotchTokens/pricing.json` (24h TTL).
2. Bundled fallback: `Resources/pricing-fallback.json` (snapshot embedded at build time).
3. Network: `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` (only when stale). Fetch failures back off exponentially (60s base, ×2, capped at 600s).

`PricingTable.rate(for:)` tries exact match → strip date suffix (`claude-sonnet-4-5-20250929` → `claude-sonnet-4-5`) → strip vendor prefix (`openai/gpt-5` → `gpt-5`) → prefix match. Returns `nil` for unknowns (cost contribution = 0, not an error).

OpenCode does **not** consult this table — it has its own pre-computed `cost` per message and we trust it.

### Logging

Use the shared `Log` namespace (`Log.swift`): `Logger` instances under subsystem `com.NotchTokens.NotchTokens` with categories `Pricing`, `ClaudeUsage`, `Credentials`. Prefer `os.Logger` over `print`. View with `log stream --predicate 'subsystem == "com.NotchTokens.NotchTokens"'`. Never log token/keychain contents.

### UI structure

- **Two presentation modes**, chosen by `Settings.displayMode` (`auto`/`notch`/`menuBar`) and wired in `AppDelegate.applyMode`. `auto` resolves to the notch panel when the main display has a notch (`NSScreen.safeAreaInsets.top > 0`), else the menu-bar item. Changing the mode rebuilds the active controller.
  - **Notch:** `NotchPanelController` + `NotchUsagePanelView` (hover-expanding pill).
  - **Menu bar:** `MenuBarController` (`NSStatusItem` + `NSPopover`) reuses `NotchUsagePanelView` in `embedded` mode — always expanded, no hover-collapse, flat background, no pin button, and driven by the controller via `receive(_:)` (the controller also owns `monitor.onSnapshotChange` to update the status-item title).
- `NotchPanelController` owns an `NSPanel` (`.borderless, .nonactivatingPanel, .fullSizeContentView`, level `.statusBar`, top-of-screen). The `.nonactivatingPanel` mask is load-bearing — without it the panel hides when the user clicks elsewhere.
- `NotchUsagePanelView` is one `NSView` that draws everything by hand (no subviews). It has two layouts (collapsed pill / expanded panel) chosen at draw time by `isExpanded`. Hover expansion is animated via `NSAnimationContext` with a custom cubic-bezier curve; the `setFrameSize` override triggers continuous redraws during animation so the bars/text interpolate smoothly.
- Hover flicker is suppressed by a debounced collapse: `mouseExited` schedules a `DispatchWorkItem` 0.18s later that double-checks `NSEvent.mouseLocation` against the window frame before actually collapsing. This absorbs phantom enter/exit events fired during `updateTrackingAreas` rebuilds.
- The view is `isFlipped = true` (top-left origin). Image draws must use `respectFlipped: true` or the image renders upside down.
- Each provider shows a near-limit warning glyph (amber triangle) and a fetch-error glyph (red circle, takes precedence). Expanded rows are clickable — a plain click opens the provider dashboard (`dashboardURL(for:)`), ⌘-click copies the stats line — with a hover highlight and trailing "open" glyph. The refresh button spins while a refresh is in flight. The whole panel exposes a live VoiceOver summary via `accessibilityLabel` (the footer buttons are not yet individually accessible).

### Settings + budget-driven limits

User settings live in `~/Library/Application Support/NotchTokens/config.json`, persisted via `SettingsStore` (an `ObservableObject` so the SwiftUI settings window binds directly to it). Codex and OpenCode budgets use a rolling 30-day $ window; `LocalUsageReader` sums their cost from the last 30 days and `UsageMonitor.refresh()` appends a synthetic `LimitWindow(name: "30d", usedPercent: rollingCost/budget * 100, resetsAt: nil)` for any provider with a budget. The UI bar/percent/caption code doesn't know or care that the window is synthetic — it renders the same way as Claude's real 5h/7d windows. Claude Code itself uses no user budget — only the live provider limit windows from Anthropic.

Settings also carry `alertThreshold` (default 80%) and `notificationsEnabled`: when a provider's peak limit window crosses the threshold, `UsageMonitor` posts a `UNUserNotification` once per crossing (re-armed when it drops back below). All new `Settings` fields must decode to a default for older configs (`decodeIfPresent` + fallback).

The settings window itself is SwiftUI inside an `NSHostingController`-backed `NSWindow` (regular, focusable — not the `nonactivatingPanel` we use for the notch), opened from the gear button in the panel footer.

### Adding a new harness

Pattern: add a `ProviderKind` case → placeholder in `UsageSnapshot.placeholder` → a `read<Name>()` method on `LocalUsageReader` (or a separate service) that returns a `ProviderUsage` → an asset in `Assets.xcassets/<name>.imageset` → wire `drawProviderLogo`, the collapsed-segment list, and the expanded-row loop in `NotchUsagePanelView`. The expanded panel size and collapsed pill width may need to grow to fit additional rows/segments.
