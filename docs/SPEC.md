# AI Quota Tray — MVP Spec

## Problem

Using Claude Code, Codex CLI, and Cursor at the same time makes it easy to hit one provider’s limit without noticing. There is no single place on macOS to see all three at a glance.

## Solution

A small **menu bar** app that shows current usage for each provider in a popover. Read-only, local-first where possible.

## Users

Single developer (you) on one Mac. No accounts UI, no cloud sync in MVP.

## MVP features

| Feature | Detail |
|---------|--------|
| Tray icon | SF Symbol `gauge.medium`; accessibility label reflects worst quota % |
| Popover | Three rows: Claude, Codex, Cursor |
| Refresh | On popover open + every 60s (configurable in settings) |
| Settings | Claude plan cap, refresh interval, launch at login |
| Errors | Per-row inline message; app never crashes on one provider failure |

## Non-goals (v1)

- History database, charts, notifications
- Burn-rate ETA, “which tool to use” recommendations
- Multi-account, multi-machine sync
- App Sandbox (deferred to v2)
- Notarization / App Store

## Data sources

### Claude Code

- **Path:** `~/.claude/projects/*/*.jsonl`
- **Method:** Parse JSONL; sum tokens in rolling **5-hour** window
- **Tokens counted:** `input + output + cache_creation` (exclude `cache_read`)
- **Cap:** User-selected plan in settings (default: Max 5x ≈ 220k tokens / 5h)
- **Reset:** `oldest_message_in_window + 5h`

### Codex CLI

- **Path:** `~/.codex/sessions/<yyyy>/<mm>/<dd>/*.jsonl`
- **Method:** Find `payload.type == "token_count"`; use last `total_token_usage` per session; sum sessions active in last 5h
- **Cap:** Unknown (ChatGPT plan limits are opaque) — show counts only, no % bar
- **Display:** `N msgs · K tokens` + window start time

### Cursor

- **Auth:** Decrypt `WorkosCursorSessionToken` from Chromium cookie DB
- **Path:** `~/Library/Application Support/Cursor/Cookies`
- **API:** `GET https://cursor.com/api/usage?user=<jwt_sub>`
- **Cap:** `maxRequestUsage` (e.g. 500 on Pro)
- **Reset:** `startOfMonth` from API

### Cursor cookie decryption

1. Read `encrypted_value` from SQLite `cookies` table
2. Keychain: service `"Cursor Safe Storage"`
3. PBKDF2: 1003 iterations, salt `"saltysalt"` (Chromium macOS)
4. AES-128-CBC decrypt `v10` prefix blob

**Permission:** Full Disk Access may be required to read Cursor’s Application Support folder.

## UI mockup

```
┌──────────────────────────────────────┐
│ Claude    1.2M / 3.0M tok   ▓▓▓░░░░  │
│           resets in 2h 14m           │
│ Codex     47 msgs · 31k tok          │
│           window started 1h ago      │
│ Cursor    312 / 500 req     ▓▓▓▓░░░  │
│           resets Dec 1               │
│ ──────────────────────────────────── │
│ ↻ Refresh                            │
│ ⚙ Settings…                          │
│ ⏻ Quit                               │
└──────────────────────────────────────┘
```

**Colors:** green &lt; 60%, amber &lt; 85%, red ≥ 85%. Unknown cap → neutral.

## Core model

```swift
struct QuotaSnapshot {
  let provider: Provider       // .claude | .codex | .cursor
  let used: Double
  let cap: Double?             // nil = unknown
  let unit: String             // "tokens" | "msgs" | "req"
  let resetsAt: Date?
  let fetchedAt: Date
  let error: String?
}
```

## Platform

- macOS 14+ (`MenuBarExtra` with `.window` style)
- Swift 5.10, no SPM dependencies for MVP
- `xcodebuild` from CLI

## Risks

| Risk | Mitigation |
|------|------------|
| Codex JSONL schema changes | Defensive parsing; fallback to raw counts |
| Cursor cookie encryption changes | Manual token paste fallback (v2) |
| Claude cap not published | User picks plan in settings |
