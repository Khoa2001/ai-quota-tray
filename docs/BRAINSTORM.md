# Brainstorm backlog

Ideas from initial planning. **Not in MVP** unless moved into [SPEC.md](SPEC.md).

## Data sources (future providers)

- Gemini CLI session logs
- OpenRouter dashboard API
- Anthropic / OpenAI usage APIs (raw $ spend)
- `codex /status` subprocess for live session quota

## Tray icon variants

- Donut/ring showing most-constrained quota
- Three stacked mini-bars (one per provider)
- Badge: minutes until soonest reset

## Popover enhancements

- “Best provider to use now” (headroom × cost heuristic)
- Per-model breakdown (Sonnet / Opus / Haiku; GPT-5 / mini)
- Per-project breakdown (Claude jsonl grouped by cwd)
- Today / week / billing-period toggle
- 24h usage sparkline
- $-equivalent vs API pricing (“is Max worth it?”)

## Proactive features

- Notifications at 50 / 75 / 90%
- Burn-rate ETA (“Claude window exhausts in 38 min”)
- Detect focused terminal CLI via `lsof` / AX API → nudge if near cap
- Weekly digest in menu

## History and analytics

- SQLite time series → Stats window with charts
- CSV export
- 30-day plan comparison report

## Multi-account / multi-machine

- Multiple Cursor cookie profiles (work + personal)
- iCloud sync of usage history

## Tech alternatives considered

| Stack | Pros | Cons |
|-------|------|------|
| **SwiftUI MenuBarExtra** ✓ chosen | Native, small, Keychain | Mac only |
| Tauri | Small, cross-platform | More setup |
| Electron | Rich charts | ~150 MB |
| Python + rumps | Fast prototype | Hard to ship signed |
| Go + systray | Single binary | Less native UI |

## Nice extras

- Hotkey `⌘⇧Q` to open popover
- Pin popover open while working
- Plugin system for custom providers (JS/Python scripts)
- Open-source / publish

## Reference projects

- [ccusage](https://github.com/ryoppippi/ccusage) — Claude Code token usage from jsonl
- Cursor usage community tools — cookie + `/api/usage` pattern
