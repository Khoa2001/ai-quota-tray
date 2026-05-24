# AI Quota Tray

Native macOS menu bar app to track usage quotas across **Claude Code**, **Codex CLI**, and **Cursor**.

**Status:** MVP implemented — menu bar app with Claude, Codex, and Cursor quota rows.

## Screenshot

![AI Quota Tray menu bar popover](docs/screenshots/tray-popover.png)

## Docs

| File | Purpose |
|------|---------|
| [docs/SPEC.md](docs/SPEC.md) | Product spec (MVP scope, data sources, UI) |
| [docs/MVP-PLAN.md](docs/MVP-PLAN.md) | Implementation plan and task checklist |
| [docs/BRAINSTORM.md](docs/BRAINSTORM.md) | Ideas backlog (v2 and beyond) |

## Decisions (locked for MVP)

- **Scope:** minimal — three provider rows, refresh on open + timer, no history DB
- **Stack:** SwiftUI + `MenuBarExtra`, macOS 14+, no third-party deps
- **Sandbox:** off for v1 (read `~/.claude`, `~/.codex`, Cursor cookie store)

## Install & run

You do **not** need to open Xcode. Build from the terminal and install like any other Mac app.

### Prerequisites

- macOS 14+
- [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) (`xcodebuild` must be on your `PATH`)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — only when editing `project.yml` or adding/removing source files:

```bash
brew install xcodegen
```

### Build and install to Applications

From the repo root:

```bash
xcodebuild -project AIQuotaTray.xcodeproj -scheme AIQuotaTray \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

cp -R build/DerivedData/Build/Products/Release/AIQuotaTray.app /Applications/
```

The app is ad-hoc signed (no Apple Developer certificate). On first launch, macOS may block it — go to **System Settings → Privacy & Security** and click **Open Anyway** if prompted.

### Run

After install, launch it like any other app:

```bash
open /Applications/AIQuotaTray.app
```

Or use Spotlight (`Cmd+Space` → “AI Quota Tray”) or Finder → **Applications**.

The app lives in the **menu bar** only (`LSUIElement` — no Dock icon). Click the tray icon to open the quota popover.

### Rebuild after code changes

Quit the running app, then repeat the **Build and install** commands above. `cp -R` overwrites the existing `/Applications/AIQuotaTray.app`.

### Launch at login

Open the tray popover → **Settings** (gear icon) → enable **Launch at login**.

## Development

Regenerate the Xcode project after editing `project.yml` or changing the file layout:

```bash
xcodegen generate
```

For a quick Debug build without installing (output stays under `build/DerivedData`):

```bash
xcodebuild -project AIQuotaTray.xcodeproj -scheme AIQuotaTray \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

open build/DerivedData/Build/Products/Debug/AIQuotaTray.app
```

## First-run checklist

1. **Sign in** to Claude Code, Codex CLI, and Cursor on this Mac (tokens/logs are read locally).

2. **Cursor** — keep Cursor signed in; the app reads `cursorAuth/accessToken` from Cursor’s `state.vscdb` or Keychain.

## Project structure

```
AIQuotaTray/
  AIQuotaTrayApp.swift          entry point, MenuBarExtra scene
  Models/
    Provider.swift              enum: .claude | .codex | .cursor
    QuotaSnapshot.swift         value type returned by each provider
    QuotaStore.swift            @MainActor store, refresh loop
  Providers/
    QuotaProvider.swift         protocol
    ClaudeCodeProvider.swift    reads ~/.claude/projects/*/*.jsonl
    CodexProvider.swift         reads ~/.codex/sessions/…/*.jsonl
    CursorProvider.swift        state.vscdb / Keychain → DashboardService API
  UI/
    TrayContentView.swift       popover root (three rows + toolbar)
    QuotaRow.swift              single provider row with progress bar
    SettingsView.swift          refresh interval, launch-at-login
  Util/
    JSONLReader.swift           shared JSONL → [[String:Any]] helper
    ChromiumCookieReader.swift  SQLite + Keychain + PBKDF2 + AES-CBC
  Resources/
    Info.plist                  LSUIElement=YES (no Dock icon)
    AIQuotaTray.entitlements    sandbox off, network.client on
    Assets.xcassets
project.yml                     xcodegen spec
```
