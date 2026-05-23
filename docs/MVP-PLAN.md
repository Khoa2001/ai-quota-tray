# MVP Implementation Plan

## Goal

Tiny menu bar app — three rows, one tray icon, no main window. Refresh on open + every 60s. Read-only, no telemetry, no DB.

## Stack

- Swift 5.10 / macOS 14+ (`MenuBarExtra`, `.menuBarExtraStyle(.window)`)
- App Sandbox **off** for v1
- Foundation, SQLite3 (cookies), CryptoKit (AES), URLSession (Cursor API)
- No third-party dependencies

## Target layout (when code exists)

```
AIQuotaTray/
  AIQuotaTray.xcodeproj
  AIQuotaTray/
    AIQuotaTrayApp.swift
    Models/
      QuotaSnapshot.swift
      Provider.swift
    Providers/
      QuotaProvider.swift
      ClaudeCodeProvider.swift
      CodexProvider.swift
      CursorProvider.swift
    UI/
      TrayContentView.swift
      QuotaRow.swift
    Util/
      JSONLReader.swift
      ChromiumCookieReader.swift
    Resources/
      Assets.xcassets
  docs/          ← you are here (temporary until code lands)
  README.md
```

## Tasks

- [ ] **scaffold** — Create Xcode project (macOS 14+, SwiftUI, MenuBarExtra, sandbox off)
- [ ] **models** — `QuotaSnapshot`, `Provider`, `QuotaProvider` protocol, `@MainActor QuotaStore`
- [ ] **claude** — Glob `~/.claude/projects/*/*.jsonl`, sum tokens in last 5h, `resetsAt`
- [ ] **codex** — Walk `~/.codex/sessions/yyyy/mm/dd/*.jsonl`, sum `token_count` in last 5h
- [ ] **cursor-cookie** — SQLite + Keychain + PBKDF2 + AES-CBC v10 decrypt
- [ ] **cursor-api** — JWT `sub`, `GET cursor.com/api/usage`
- [ ] **ui** — `TrayContentView`, `QuotaRow`, Refresh / Quit, settings sheet
- [ ] **refresh** — 60s timer + on-open; `async let` with 10s timeout per provider
- [ ] **settings** — Claude plan picker, refresh interval, launch-at-login (`SMAppService`)
- [ ] **readme** — Build steps + Full Disk Access note (fold into root README when done)

## Provider notes

### ClaudeCodeProvider

- Glob `~/.claude/projects/*/*.jsonl`
- Line shape: `{ timestamp, message: { usage: { input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens } } }`
- Window: `[now - 5h, now]`
- Cap: `UserDefaults` (default Max 5x = 220_000)

### CodexProvider

- Last `token_count` per session file
- Sum sessions with activity in last 5h
- No cap bar in UI

### CursorProvider

- Cookie name: `WorkosCursorSessionToken`
- API: `https://cursor.com/api/usage?user=<sub>`
- Sum `numRequests`; cap = `maxRequestUsage`

## Refresh logic

`QuotaStore.refresh()`:

```swift
async let claude = ClaudeCodeProvider().fetch()
async let codex = CodexProvider().fetch()
async let cursor = CursorProvider().fetch()
// each with 10s timeout; errors → QuotaSnapshot.error
```

`Timer.publish` + refresh when popover appears.

## Build / ship

- `xcodebuild` from CLI
- Ad-hoc sign for personal use
- Notarization → v2

## Out of scope (v2)

History DB, sparklines, notifications, burn-rate, recommendations, multi-account, sandboxing.
