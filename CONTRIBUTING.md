# Contributing to NotchTokens

Thanks for your interest in improving NotchTokens — a notch-anchored macOS menubar
app that tracks token usage and cost for Claude Code, OpenAI Codex CLI, and OpenCode.

## Prerequisites

- macOS 13 (Ventura) or later
- Xcode 16 or later (the project uses `PBXFileSystemSynchronizedRootGroup`)

There is no Swift Package or external dependency manager — just the Xcode project.

## Build, run & test

```bash
# Build (debug)
xcodebuild -scheme NotchTokens -configuration Debug -destination 'platform=macOS' build

# Run the test suite
xcodebuild test -scheme NotchTokens -configuration Debug -destination 'platform=macOS'

# Run the app: open the built .app from DerivedData, or hit ⌘R in Xcode
```

The Debug configuration builds with `SWIFT_STRICT_CONCURRENCY = complete` and treats
warnings as errors, so a clean Debug build is the bar. Release is left lenient.

## Code style

Formatting and linting use Apple's `swift format` (a Swift toolchain subcommand — no
extra install), configured by [`.swift-format`](.swift-format).

```bash
# Format in place
xcrun swift format format --in-place --recursive --configuration .swift-format NotchTokens NotchTokensTests

# Lint
xcrun swift format lint --strict --recursive --configuration .swift-format NotchTokens NotchTokensTests
```

A pre-commit hook formats staged Swift files automatically. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

## Commits

Use Conventional Commit prefixes — only `feat:`, `fix:`, and `chore:`. Keep subjects
short and imperative, e.g. `fix: guard stale /model callback`.

## Pull requests

1. Branch off `main`.
2. Make your change; add or update tests under `NotchTokensTests/` where it makes sense.
3. Ensure `swift format lint --strict` is clean and the test suite passes.
4. Open a PR. CI (GitHub Actions) runs lint + a Debug build/test + a Release build on
   every PR and must be green before merge.

## Project layout & architecture

See [AGENTS.md](AGENTS.md) for the data-flow overview, per-provider parsing details,
the pricing pipeline, the hand-drawn UI, and the pattern for adding a new harness.
