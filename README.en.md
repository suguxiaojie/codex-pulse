<div align="center">

<p><a href="README.md">简体中文</a> · <strong>English</strong></p>

# Codex Monitor for macOS

**A native macOS app that brings Codex quotas, tokens, cost estimates, live tasks, reset signals, and local sessions into one place.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![SwiftUI + AppKit](https://img.shields.io/badge/SwiftUI%20%2B%20AppKit-native-F05138?style=flat-square&logo=swift&logoColor=white)](Package.swift)
[![Universal 2](https://img.shields.io/badge/Universal%202-arm64%20%2B%20x86__64-2563EB?style=flat-square)](scripts/build-app.sh)
[![Local first](https://img.shields.io/badge/data-local%20first-10B981?style=flat-square)](#data-sources-accuracy-and-privacy-boundaries)
[![License: MIT](https://img.shields.io/badge/License-MIT-F7DF1E?style=flat-square)](LICENSE)

</div>

> [!IMPORTANT]
> The latest version is [`v1.7.0 (Build 25)`](https://github.com/suguxiaojie/codex-notch-monitor/releases/tag/v1.7.0). The Release provides separate DMGs for Apple Silicon `arm64` and Intel `x86_64`; choose the package that matches your Mac.

> [!TIP]
> **Sponsor: CoverAI top-up service** — [Visit CoverAI](https://www.coverai.store/)

## What's new in v1.7.0

- Read-only task monitoring uses desktop IPC and local logs. Hook ingestion is disabled in this release while existing Hook configuration is preserved. The island does not submit approvals, answers, or messages. Completion feedback retains per-turn tokens and confetti before returning to a persistent quota/idle banner.
- The island includes a usage dashboard and in-panel quota-reset details. Resetting uses the real account endpoint, requires a second confirmation, and cannot be undone.
- Session management handles App Server pagination and compressed history. Markdown/HTML exports preserve question grouping, collapsible progress, redaction, and backups. HTML embeds recovered images with zoom, pan, and reset; Markdown uses a matching assets directory. Missing images are explicitly identified.
- Usage and Cost share cyan charts, smooth trends, and slender short-period bars. Official prices refresh automatically; model mappings and unknown rates remain visible. Community reset associations retain their original detection evidence.
- The menu bar always shows a quota ring and percentage. Settings, session tools, and quiet text refresh buttons share a consistent dark style.

Separate Apple Silicon and Intel DMGs are ad-hoc signed and are not notarized by Apple. Intel compilation and package validation are covered; Intel hardware testing and some animation-frame checks remain pending.

## Table of contents

- [What this app does](#what-this-app-does)
- [Interface preview](#interface-preview)
- [Feature details](#feature-details)
- [Data sources, accuracy, and privacy boundaries](#data-sources-accuracy-and-privacy-boundaries)
- [System requirements](#system-requirements)
- [Build and install from source](#build-and-install-from-source)
- [First-run setup and permissions](#first-run-setup-and-permissions)
- [Hook events and status mapping](#hook-events-and-status-mapping)
- [Session export, import, and recovery](#session-export-import-and-recovery)
- [Local files and network requests](#local-files-and-network-requests)
- [Development, testing, and builds](#development-testing-and-builds)
- [FAQ](#faq)
- [Known limitations](#known-limitations)

## What this app does

Codex Monitor is a native macOS menu bar app built with SwiftUI and AppKit. It organizes information that would otherwise be spread across Codex App Server, local session logs, Codex lifecycle Hooks, and public community signals into three usage layers:

1. **Menu bar and Glance panel**: quickly check the current account's quota, reset time, Credits, cost estimate, and token activity.
2. **Activity Island and task status**: follow task execution, tool calls, approval waits, and completion without switching back to Codex.
3. **Monitor Center**: inspect Usage Analysis, Cost Estimates, Dynamic Center, Session Management, Menu Bar & Panel, Setup & Permissions, and Activity Island Settings in full detail.

The app does not collapse “official quota,” “local statistics,” “community forecasts,” and “local inference” into one confidence level. Both the UI and this document label their sources explicitly.

## Interface preview

### Expanded Glance panel and transparency

<p align="center">
  <img src="docs/images/glance-transparent-retina.png" alt="Codex Monitor transparent expanded Glance panel" width="38%">
</p>

Glance focuses on the current account. It combines weekly quota, Spark quota, Credits, the quota reset action, estimated cost, today's and 30-day token usage, and token activity in one narrow panel. The panel uses an adjustable translucent dark background; the screenshot preserves the code and colors behind the window so the real background-through-panel effect is visible. The bottom actions refresh all data, open Dynamic Center, and enter the full Monitor Center.

### Usage and Cost

<p align="center">
  <img src="docs/images/monitor-center-usage-retina.png" alt="Codex Monitor Usage page" width="49%">
  <img src="docs/images/monitor-center-cost-retina.png" alt="Codex Monitor Cost page" width="49%">
</p>

Usage and Cost share account scope, desktop system typography, and card language while using periods suited to each dataset. Core metrics and trends appear before activity heatmaps and details. The resizable window also responds to macOS Reduce Motion, Reduce Transparency, and Increase Contrast settings.

### Dynamic Center

<p align="center">
  <img src="docs/images/dynamic-center-retina.png" alt="Codex Monitor Dynamic Center" width="82%">
</p>

Dynamic Center separates current-account quota, third-party community forecasts, and locally observed recovery records. Quota percentages come from Codex App Server; Tibo posts, the reset timeline, and experimental probability forecasts come from `codex-reset.com`, which is not an official OpenAI API. Expired signals are no longer pinned, and reply context, verification status, and complete expandable text remain visible.

### Session Management

<p align="center">
  <img src="docs/images/session-management-retina.png" alt="Codex Monitor Session Management page" width="82%">
</p>

Session Management treats all local user sessions as a searchable library with project/session/path search, status filters, a native selectable list, independently expandable projects, and selected-session details. The current login is shown separately from the library scope; historical sessions that predate reliable attribution remain explicitly labeled as “Unattributed.” Import, export, recovery results, and backups live in an on-demand operations area.

### Panel Settings and Activity Island Settings

<p align="center">
  <img src="docs/images/panel-settings-retina.png" alt="Codex Monitor Panel Settings page" width="49%">
  <img src="docs/images/activity-island-settings-retina.png" alt="Codex Monitor Activity Island Settings page" width="49%">
</p>

The menu bar always shows a quota ring and percentage; the former task, density, and content selectors have been retired without rewriting saved preferences. Content/Appearance uses sliding navigation, and opacity uses the continuous island slider. Session toolbar controls and quiet text refresh actions share the same dark styling.

Settings retains the original Monitor Center sidebar and other feature entries. Activity Island is one child page, following QuotaView's Material, Glass Degree, Privacy, Width, Task Effects and Automatic Opening controls with a wallpaper-backed live preview. Panel Settings still controls which quota, Credits, reset, token, and cost modules appear in Glance.

### Menu-bar quota ring



<p align="center">
  <img src="docs/images/menu-bar-quota-rings.png" alt="Codex Monitor menu bar quota ring states" width="58%">
</p>

The quota ring and percentage form a stable menu-bar baseline. The native button sizes to its current content without reserving empty task or rotation slots. While a task is running, its phase, project, and current-turn tokens follow that baseline, with K/M/B token abbreviations. When space is limited, task content can progressively compact by priority or rotate project and current-turn token pages within available space. Reset countdowns remain in the tooltip and Glance. Project names truncate by measured width, and multi-project token counts remain isolated by session.

## Feature details

### 1. Menu bar and Glance overview

Glance is the panel used most often in daily work. It shows only the **current real account** and does not mix historical accounts into the compact view.

- Shows the current account, plan type, and connection state.
- Displays the Codex weekly quota, short-window quota, and any other quota buckets returned by App Server.
- Shows remaining percentage, consumed percentage, and a precise reset countdown for each window independently.
- Supports separate Spark and other quota windows; missing windows do not create empty placeholder cards.
- Shows the current Credits balance.
- Displays available quota-reset credits, their expiration, and the manual reset action.
- Shows the local API-equivalent cost estimate, today's tokens, 30-day tokens, and token activity.
- Glance keeps its own Week / Month / Three Months / Six Months observation ranges and does not change the independent selectors in Monitor Center cards.
- Provides bottom actions for refresh, Monitor Center, Activity Island Settings, and quit.
- Panel Settings can show or hide quota, cost, Credits, token activity, and reset modules individually and adjust panel opacity.

A manual reset means that the user actively consumes a reset credit from the reset card in this app. It is distinct from a natural expiration reset and a temporary reset announced by Tibo.

### 2. Usage: tokens and project activity

Usage calculates tokens from local structured Codex session logs. It does not depend on screen recognition and does not present a cumulative curve as a trend chart.

- Scans both `~/.codex/sessions/` and `~/.codex/archived_sessions/`.
- Deduplicates structured token events so a session that briefly exists in both active and archived storage is not counted twice.
- Shows Token Summary and Trend first; activity follows the summary period by default, with optional independent 30 Days / 90 Days / Six Months.
- Combines account scope and Week / Month / Three Months in one filter bar. Metrics show their local account scope; the main reading surface is opaque. Project ranking supports all projects, detail sheets, and navigation to all local sessions for that project.
- Shows total tokens split into input, output, and cache.
- Displays session count, project count, and per-project usage ranking.
- Uses the full project path as the stable aggregation key while preferring the local Codex sidebar alias as the display name.
- Trend displays non-cumulative calendar-day buckets and drives the project ranking for the same period.
- The Activity card labels its scope. Ranges up to 30 days use daily bars; 90-day and six-month ranges use heatmaps.
- Hovering a trend point or activity cell reveals the exact time and token count.
- When reliable structured evidence shows that a session's project path changed, the latest path updates its project attribution.
- Account scope can show combined statistics, an observed account, or unattributed history. Baseline history is never guessed to belong to the current account.

### 3. Cost: API-equivalent estimates

Cost reuses the same local structured-log scan and account scope as Usage, with periods suited to cost analysis.

- Combines account scope and period filters. Activity follows the selected period by default; an explicitly labeled independent 30 Days / 90 Days / Six Months range is available. Daily cost uses hourly bars, weekly/monthly cost uses daily bars, and ranges over 30 days use heatmaps. Future hours remain empty.
- Uses Day / Week / Month for API-equivalent Cost Trend.
- Log Sources aligns Token totals and API-equivalent cost in two columns, lists official and supplementary synchronization times separately, and folds model mappings into pricing details. Unknown-price warnings remain visible.
- Calculates input, output, cache-write, and cache-read tokens separately.
- Displays token throughput, hourly or daily cost trends, and local log sources.
- Official Standard prices refresh every 24 hours from the public OpenAI Markdown pricing page, then costs are recalculated. Only successful synchronization advances its displayed timestamp; failures retain valid cached prices or the bundled official snapshot and retry after six hours. The public community catalog fills in other models and cannot override official prices.
- Validates the remote catalog's schema, size, numeric ranges, and cache. If refresh fails, the app continues with the latest verified cache or embedded fallback.
- GPT-6 Astra, GPT-6.1 Sol, GPT-6 Sol, GPT-6 Luna, and the GPT-5.6 family use official OpenAI standard rates, including the documented long-context multipliers above 272K input tokens.
- Unknown models are never assigned a guessed price. They are listed in the UI and counted as `$0` in the estimate.
- Internal Codex auto-routing models are mapped to the primary model only when the local timeline provides evidence for the model used at that time; the UI discloses the mapping.

> [!WARNING]
> Cost is an **API-equivalent estimate** based on public model prices. It is not a ChatGPT/Codex subscription bill and does not mean the user will be charged that amount.

### 4. Dynamic Center: official quota, Tibo posts, and reset timeline

Dynamic Center preserves the complete feed while using hierarchy and filters to reduce visual noise. Live posts, the reset timeline, and local recovery use shared sliding navigation with a compact content filter.

- The top Official Quota card reads `account/rateLimits/read` and displays real quota windows and health status.
- Community forecasts are labeled separately with their confidence level and are never presented as official conclusions.
- Feed mode keeps the complete relevant `@thsottiaux` timeline and groups entries by date.
- Supports All / Reset Signals / Quota Updates filters.
- Ordinary posts no longer repeat a generic Dynamic tag; only Limits, Reserve, Fulfilled, Reset, and Preview use semantic content tags.
- Live Radar, Archived Evidence, and confidence are status metadata shown as text or dots rather than encoded through content-tag color.
- Recovery History remains a neutral action with a separate count instead of sharing forecast-confidence or content-tag capsule styling.
- A pinned signal highlights the latest confirmed or otherwise important quota event.
- Reset Timeline presents previews, arrival, confirmation, archival, and evidence links as related events rather than renaming an ordinary list.
- Each item keeps its original link, source account, publication time, and engagement counts and can open the original post on X.
- On macOS 15 and later, the system Translation framework can translate individual items into Simplified Chinese. Translations are cached only in process memory.
- If the network or upstream source fails, the latest validated cache remains visible with an explicit delayed-data warning.

Radar data is read from these public endpoints:

```text
https://codex-reset.com/api/feed?locale=zh
https://codex-reset.com/api/timeline?locale=zh
https://codex-reset.com/api/forecast?locale=zh
```

The client validates the data version, source scope, `@thsottiaux` profile, time fields, X links, item limits, and probability ranges. Passing those checks only proves that a response follows the current contract; it does not turn a third-party source into an official OpenAI API.

### 5. Quota recovery monitoring and three reset types

The app compares before-and-after states for the same quota window and account, then combines App Server `resetsAt`, user actions, and Tibo evidence to classify the recovery:

| Type | Evidence | Meaning |
|---|---|---|
| Tibo reset | The recovery time matches a validated Tibo reset signal | A temporary or planned reset announced by the community channel and observed on the account |
| Scheduled reset | The quota window recovers near `resetsAt` | Normal window expiration |
| Manual reset | The user consumes a reset credit from this app's reset card | User-initiated reset |

Quota jumps without enough evidence first enter a pending-verification state, so first launch, account switching, or transient API responses do not immediately trigger false notifications. New snapshots retain an available account identifier and account changes establish a fresh baseline. After three hours, unresolved recoveries are labeled historical and unclassified. Community refreshes automatically persist eligible historical associations and display them as Tibo resets without requiring individual confirmation. The original reason and quota changes remain intact, manual classifications take precedence, and an automatic backup precedes the update. Reloading does not repeat tagging or backups; historical account ownership is not guessed and old notifications are not sent. Details distinguish recovery, timeline and available post-publication times. Source-time discrepancies remain visible in association details and still prevent strict live confirmation; reset-credit events do not prove an executed reset. Recovery history supports type filters and lets the user correct the **display type**. A correction writes only `userDisplayType`; the original reason remains intact, and a timestamped backup is created before saving.

### 6. Live tasks and Activity Island

The expanded Island's quota button or floating quota capsule opens a QuotaView-style usage page with back, pin, collapse and refresh controls. Account quota, Credits and reset credits belong to the current login; Tokens and activity prefer current-account account/usage/read summaries (UTC dates); usage-page costs follow QuotaView’s fixed $0.50-per-million-token proxy over official UTC daily totals; the latest day is the last known bucket. The dedicated Cost page retains local model-specific input/output/cache pricing. If official usage is unavailable, tokens fall back to local history, with lifetime totals populated after the full background scan and 180 days of local activity. Heatmaps support daily, weekly and cumulative modes. Both cost methods are estimates, not bills. Privacy mode hides usage content; the reset ticket opens an in-Island detail page with a reversible card flight. Reset requires a separate explicit confirmation before the existing official API is called; unavailable/stale quota, unknown account, privacy mode and in-flight requests disable submission. See [implementation notes](docs/quotaview-usage-panel.md).

Session inventory and local detailed usage support both `.jsonl` and Zstandard `.jsonl.zst` rollouts through read-only streaming, with session/event deduplication and separate internal-thread classification. Newly discovered history does not imply current-account ownership. Readable exports decode streams directly; portable exports normalize to JSONL only inside their staging directory and preserve source files. See [compressed rollout reading](docs/compressed-rollouts.md).

The current local trial build pauses Hook data ingestion and uses read-only desktop IPC plus incremental local logs for task state. Hook installation and configuration remain intact, but the app does not poll, read or consume the Hook inbox. Setup & Permissions displays the paused status.

- Supports starting, using tools, thinking, waiting for approval, completed, and session-ended phases.
- Aggregates multiple sessions under the same project path and shows the number of running sessions.
- Distinguishes reading, searching, editing, validation, image inspection, and ordinary commands.
- Truncates command summaries and masks common token, key, and password arguments.
- Retains menu-bar capacity protection and adaptive layout. Automatic uses the widest safe layout that currently fits, progressively compacts after crowding, and expands again in small steps when space returns.
- When space is limited, rotates project and current-turn token pages or progressively compacts them by status priority. The quota ring and percentage remain stable; hover retains reset timing and complete per-project and per-session context.
- Menu-bar current-turn tokens are projected from structured session events and isolated by session and turn. An incomplete boundary remains explicit. Island cards follow QuotaView's session-cumulative count; the two accounting scopes remain independent.
- Completion feedback requires explicit terminal evidence for the matching turn. Cancellation, inactivity timeouts, and disappearing sources do not imply success. Unchanged cached logs are reevaluated for freshness, and retired-turn events cannot replace an observed newer turn.
- Expanded mode presents one card per session with cumulative session tokens and status counts. Up to four rows are visible; native scrolling preserves the reading anchor. Cumulative counts read legacy `token_count.total_token_usage` or native `token_usage_record.thread_token_usage` totals without adding cached/reasoning breakdowns again; missing totals show “— tokens”. Active tools show their current summary; thinking shows the latest public assistant progress rather than stale tool output.
- The primary banner remains resident. Completion feedback transitions to a quota/idle banner, showing “All tasks completed” while receipts remain and “No running tasks” afterward. Idle content has no task orb, task card or running effect; hover/click still opens the empty state. Unavailable/private quota shows “—”. The floating capsule toggle does not hide the primary banner; lock/sleep can temporarily hide it.
- Compact mode reuses QuotaView's fitting layout: status orb and scrolling “status · current action” on the left, session count and attention indicators on the right, with camera clearance. Cold-start tasks form a compact baseline. New task/turn/completion events open an automatic preview with a fixed deadline; token/tool/text updates and entering an already automatic preview do not postpone it. Hovering compact mode for about 0.15 seconds or clicking opens manually; leaving for 0.45 seconds or clicking outside closes it. Pinning and pending confirmation keep it open. New completions briefly take compact focus, and reserved-width session/completion counts alternate every three seconds.
- An optional floating usage capsule appears below the visible island, enabled by default with Dark/Light tones. It shows official Codex 5-hour and weekly quota/reset countdowns and narrows for weekly-only accounts. It follows compact/expanded geometry, hides in privacy mode, reuses existing quota snapshots without additional requests, and shows unknown values after failed refreshes. Settings previews use isolated sample data.
- The expanded surface defaults to 680 pt and offers Liquid Glass or Classic material with adjustable glass degree. Cards show model, reasoning effort and observed duration. The selected card uses the complete QuotaView State Smoke, Quantum Noise or Liquid Wave renderer; decorative effects are not measured completion percentages.
- Native and custom tool calls share the activity parser. Read-only file-change observation coalesces recent session updates while periodic discovery and reconciliation remain enabled, reducing short-call display lag. Only safe action summaries are extracted; argument bodies are not displayed.
- The panel supports pinning, session selection, refresh and settings. Settings previews share the production card and effect components and preview all three effects.
- Island settings share Panel Settings' cards, typography, spacing and native controls, grouped into preview, material and size, display and privacy, task effects, and automatic expansion. QuotaView's live preview and effect rendering are retained. Glass degree and expanded width use continuous damped sliders with preview updates capped at 20 per second and an exact value commit on release, plus keyboard and accessibility adjustments; capsule tone uses a sliding selection plate. These transitions respect Reduce Motion. Privacy mode masks task, project, action, model and token data, including accessibility text. Automatic popups can be disabled independently of hover; duration is 1–10 seconds, defaulting to 3. Legacy scale, placement, selectable orb, opacity, disable/mode and completion-hide settings and runtime branches are removed. Their stored values no longer affect the island. Menu-bar density, overflow and task activity remain independent controls in Panel Settings.
- Completed cards show a green check orb and both turn consumption and cumulative session tokens, using “—” for missing turn data. A real active-to-completed transition triggers a brief confetti burst from the island edges. Repeated refreshes, historical completions, resuming a hidden panel and Reduce Motion do not replay it. Status text is deduplicated. Sparse updates retain known metadata within the same turn; terminal evidence freezes duration while final cumulative tokens can still arrive. Classic/Glass material applies consistently to the native task list and settings preview.
- Footer counts follow the actual starting, thinking, working, awaiting-confirmation, completed, cancelled and failed phases, grouping concurrent sessions independently.
- Manual hover previews remain readable while hovered and can be collapsed explicitly. Automatic-preview deadlines remain independent of manual and pinned states. Routine action/token updates do not reopen compact mode, while new approval waits draw attention. Transparent canvas space releases pointer events.
- Expansion and collapse share a 380 ms native path transition with 230 ms content fades. Rapid reversals continue from the displayed geometry. Hidden/occluded content and system reduced-motion states stop continuous effects. Classic material is opaque black. Production and preview share screen/notch width constraints and fixed compact geometry. Unpinning collapses immediately; new approval waits gain focus and use the upstream edge reminder and breathing effect.
- Approval waits use a high-priority state; normal work and idle states use different colors and breathing rhythms.

Session initialization follows QuotaView's distinction between a session and an active turn: ordinary `SessionStart` does not create a task. Hooks in every phase may only supplement an independently verified active user session/turn; they never create standalone cards. Unassociated working/tool/waiting events, internal threads and settled turns cannot be revived by Hooks. Incoming Hooks prioritize the indexed rollout path; project paths never establish conversation identity.

Hooks are optional: read-only desktop IPC supplies owner/epoch/turn/revision-validated running, waiting, completion, cancellation and failure states, while incremental local logs supply tool activity and tokens. Unavailable desktop connections fall back to local logs, with Hook data excluded during this trial and no invented confirmation evidence. Setup & Permissions reports native connectivity independently. The island does not submit approvals, answers or messages.

### 7. Session Management and account continuity

Session Management works with local Codex sessions and projects on the same Mac. It does not collapse “local file exists,” “visible to App Server,” and “visible in the Codex sidebar” into one state.

- Uses Codex App Server `account/read` for current-account information.
- Raw account identifiers are not stored directly. ChatGPT sign-in uses a fingerprint generated with a random local salt and displays only a masked email address.
- The account-state watcher observes only modification time, size, and file number for the Codex account-state file; it does not read the file contents.
- Inventories active and archived JSONL together and reports projects, sessions, archived sessions, pending recovery, and unattributed history.
- Sessions that predate the attribution baseline remain Unattributed and are never assigned automatically to the current account.
- Project and session actions are grouped into ellipsis menus so export and deletion do not dominate the list hierarchy.
- Supports redacted Markdown, redacted self-contained HTML, raw recoverable session bundles, and complete project transfer bundles.
- Includes security preflight, manual remapping for missing project paths, duplicate-ID skip or explicit ID regeneration, transaction backups, App Server visibility checks, and rollback.
- Supports permanently deleting one session, removing only the Codex project registration, or moving an explicitly selected project directory to macOS Trash. Each write action requires another confirmation in the UI.

### 8. Panel Settings, Setup, and Permissions

Monitor Center currently contains seven pages:

| Page | Purpose |
|---|---|
| Usage | Token, session, project, and quota overview |
| Cost | API-equivalent cost and local log sources |
| Dynamic Center | Official quota, Tibo posts, forecasts, and reset timeline |
| Session Management | Account continuity, local sessions, import, export, and recovery |
| Panel Settings | Controls quota, usage, cost, and actions in Glance |
| Setup & Permissions | First-run setup, notification permission, Hook installation/review, connection verification, and app updates |
| Activity Island Settings | A child page for material, privacy, width, task effects and automatic opening |

The Setup & Permissions maintenance page includes an app-update card. It checks GitHub Latest Release after launch, repeats automatically every 30 minutes while the app runs, reuses cache younger than 30 minutes when Settings opens, and also supports an immediate manual check. When an update is available, it selects the correct DMG for Apple Silicon or Intel Mac, shows release notes, file size, and a shortened SHA-256 digest, and offers Remind Later, View Notes, and Download DMG actions. The icon rotates while checking and uses a subtle breathing effect for an available update; Reduce Motion disables continuous animation. This version guides the user through download and manual installation and never replaces `/Applications` automatically. Only a Release with a higher semantic version is an update; pushing `main` or replacing same-version assets is not.

## Data sources, accuracy, and privacy boundaries

### Data sources and confidence

| Data | Source | Confidence category | Refresh and limitations |
|---|---|---|---|
| Current account and quota windows | Codex App Server: `account/read`, `account/rateLimits/read` | Official local interface | Manual refresh, app refresh cycle, and App Server updates; stale values or `--%` are shown when unavailable |
| Usage tokens | Structured `token_count` events from local `sessions` / `archived_sessions` | First-party local record | Scanned and cached on refresh; limited to local history that remains readable on this Mac |
| Live task phase | Desktop IPC and incremental local logs, with optional lifecycle Hooks | Local events and a version-specific desktop protocol | Falls back when IPC is unavailable; no approval/answer submissions |
| Cost | Local tokens × public model prices | Local estimate | API-equivalent estimate, not a subscription bill; unknown models are not priced |
| Tibo posts and reset timeline | `codex-reset.com` aggregation of public X content | Third-party community source | Refreshes every 3 minutes by default; older than 10 minutes is considered potentially stale; a validated cache survives upstream failure |
| 24h / 48h reset probability | `codex-reset.com` forecast | Third-party forecast | An observational aid, not an OpenAI commitment |
| Reset type | Local rules using App Server windows, user actions, and Tibo evidence | Local evidence-based inference | Insufficient evidence remains pending; users can correct only the display type |

### What normal monitoring does not read

- Does not read or output `auth.json`, cookies, tokens, API keys, or passwords.
- Hook Helper retains only `session_id`, `turn_id`, `cwd`, `hook_event_name`, `model`, `tool_name`, and receive time.
- Usage/Cost extract usage fields. Task logs retain structural events and bounded, sanitized public assistant progress, without displaying private reasoning or full tool output. Desktop IPC transiently parses conversation state and passes only the title, current turn, phase, start time and waiting indicators to the monitoring model; raw state streams are neither saved nor logged.
- Does not scan project source code to calculate Usage or Cost.
- Does not upload local account, project, session, token-usage, or quota data to the dynamic source or model-price catalog.

### User-initiated operations that require special care

- When exporting redacted Markdown or HTML, the app reads the selected session's user messages and final responses locally to generate the readable file and applies sensitive-text masking.
- Raw `.codexmonitorbundle` and full project transfer bundles may contain prompts, source code, terminal output, absolute paths, images, and other attachments. They are private backups and should not be uploaded publicly.
- Session import, recovery, deletion, project transfer, Hook install/uninstall, and manual quota reset write local state. The app shows the scope before the operation and creates backups where supported.
- CoverAI and X links open external websites only after the user clicks them.

## System requirements

### Running a built app

- macOS 13 Ventura or later.
- Apple Silicon Mac or 64-bit Intel Mac.
- Codex/ChatGPT Desktop installed and signed in. Official account and quota data are unavailable when signed out.
- macOS 15 or later is required for system Translation of dynamic content.

### Building from source

- Xcode Command Line Tools or Xcode with a Swift 6 toolchain.
- `git`, `swift`, `codesign`, and `lipo`; DMG creation also uses the system `hdiutil`.
- No third-party Swift Package dependency is required.

## Build and install from source

### 1. Clone and verify

```bash
git clone https://github.com/suguxiaojie/codex-notch-monitor.git
cd codex-notch-monitor
./scripts/test.sh
```

### 2. Build for the current Mac

```bash
./scripts/build-app.sh native
open build/CodexNotchMonitor.app
```

Output:

```text
build/CodexNotchMonitor.app
```

### 3. Build Universal 2

```bash
./scripts/build-app.sh universal
```

The Universal build compiles both the main app and `CodexMonitorHook` for `arm64` and `x86_64`, merges them with `lipo`, and applies an ad-hoc signature after the merge.

### 4. Install to `/Applications`

```bash
./scripts/install-app.sh universal
```

The installer:

1. Rebuilds and signs the app.
2. Backs up an existing `/Applications/CodexNotchMonitor.app` to `build/backups/`.
3. Replaces the app and verifies its signature.
4. **Preserves the current Hook configuration and does not modify `~/.codex/hooks.json` automatically.**
5. Launches the newly installed app.

### 5. Build a DMG

```bash
./scripts/build-dmg.sh
```

By default this creates a read-only compressed Universal 2 image:

```text
build/CodexNotchMonitor-v<version>-universal.dmg
```

The app currently uses an ad-hoc signature and is not notarized with Apple Developer ID. If Gatekeeper blocks the first launch, verify the source and allow it from System Settings → Privacy & Security. Do not use untrusted scripts to remove security attributes across the system.

## First-run setup and permissions

First launch opens Setup & Permissions automatically. The flow can be skipped and reopened later from Monitor Center. The current step is persisted, so leaving the page or restarting the app resumes from the same point.

### Five-step flow

1. **Welcome**: explains local data scope, optional capabilities, and what the app does not read.
2. **Environment Check**: read-only checks for Codex CLI, the bundled Helper, and whether `~/.codex/hooks.json` can be parsed safely. This page does not modify files or show future review states early.
3. **Notifications**: macOS notification permission is requested only after the user clicks Allow Notifications.
4. **Hooks**: after user confirmation, backs up and merges Hook configuration, installs the stable Helper, and leaves trust approval to the user in Codex's native review menu.
5. **Verification**: fully quit and restart Codex, then send a real message. The app reports a healthy connection only after receiving the first Hook event matching the current installation hash.

### What Hook installation changes

Only after the user clicks and confirms Install/Update Hooks will the app:

- Copy the Helper to:

  ```text
  ~/Library/Application Support/CodexNotchMonitor/Helpers/CodexMonitorHook
  ```

- Back up the existing `~/.codex/hooks.json` and previous Helper.
- Merge nine current-user event types while preserving existing Hooks from the user or other apps.
- Use a shell-quoted stable Helper path so spaces in `Application Support` work correctly.
- Set a 2-second maximum wait for every synchronous Hook.
- Make the Helper write only a small local event file and perform no network request.

After installation, the user must still complete Codex security review personally:

1. Click Enter Security Review or Open Hooks Manager in the app.
2. If Codex shows the native `Hooks need review` menu, use the arrow keys to choose `2. Trust all and continue`, then press Enter.
3. If Codex skips the startup review menu, the launcher opens the official `/hooks` page automatically; inspect and trust the current Hook definition in Codex.
4. If the Terminal window closes, you can reopen it immediately from the app without waiting for a fixed timeout.
5. Return to the app and confirm I Completed Security Review.
6. Use `Cmd + Q` to quit Codex completely, reopen it, and send a normal message.

The launcher uses Expect only to provide a real PTY, detect Codex's native review menu, and enter the official `/hooks` command from a normal CLI prompt. It immediately returns keyboard control to the user and never chooses a trust action, bypasses Hook trust, or creates a test session to fake a successful connection.

### Hook status reference

| Status | Meaning | Recommended action |
|---|---|---|
| Not installed | The current configuration does not contain the complete Codex Monitor Hooks | Back up and install, or skip |
| Hook update required | An old definition exists or the installed Helper does not match the current app | Back up and update, then review again |
| Hook status confirmation required | The app has no local confirmation for this definition and cannot claim that Codex distrusts it | Inspect `/hooks`; if all entries are Active, confirm in the app |
| Security review required | The current definition differs from the previously confirmed definition | Review and trust the new definition in `/hooks` |
| Opening Hooks manager | The app is launching the Codex terminal | Wait about 1.5 seconds; reopen immediately if the window closes |
| Waiting for first real message | The review hash is recorded, but the current installation has not produced a real event | Fully quit and restart Codex, then send a normal message |
| Connected | A real Hook event matching the current installation was received | No action required |
| Hooks configuration cannot be parsed | `hooks.json` is not safe to merge | Fix the configuration and retry; the app will not overwrite it |

Command-line users can also run `scripts/install-hooks.py`. Inspect `/hooks` after installation; trust is required only when Codex marks a new or changed definition for review. The in-app flow is recommended because it shows the installation hash, status confirmation, and first-real-event verification.

## Hook events and status mapping

| Codex Hook | App phase |
|---|---|
| `SessionStart` | Starting |
| `UserPromptSubmit` | Starting |
| `PreToolUse` | Using tools |
| `PostToolUse` | Thinking |
| `PermissionRequest` | Waiting for your approval |
| `SubagentStart` | Thinking |
| `SubagentStop` | Child task stopped; does not independently confirm parent completion |
| `Stop` | Completed |
| `SessionEnd` | Session ended |

Helper always exits successfully so a monitoring failure cannot block normal Codex work. The app consumes only the structured events written by Helper and never forwards Hook input to the network.

## Session export, import, and recovery

### Readable exports

- **Markdown**: suitable for private reading and handoff, with sensitive-text masking by default.
- **Self-contained HTML**: styled and directly viewable in a browser, with the same redaction behavior.
- Readable Markdown and HTML group content by user question, separate prompts from answers, and collapse progress updates. Explicit `commentary` / `final_answer` phases take precedence; legacy logs use the last reply. HTML uses a 736 px reading column with right-aligned prompts and includes nested lists, question navigation, offline search, tables, and code copying with a local-file fallback. Markdown folding depends on the viewer. Redaction and recoverable backups retain their existing behavior.
- Export shows permission, scanning, generation, compression, and completion states. It never calls `thread/start` or `turn/start`, creates no new session, and consumes no quota.

User-referenced images are recovered from embedded log data or existing local image files. HTML embeds static PNGs with thumbnails and a keyboard-accessible viewer, including cursor-centered wheel zoom, pointer dragging, double-click / 0 / button reset, and a fresh view on image switches. Markdown writes a sibling `<filename>.assets/` directory with relative references; move it together with the `.md` file. Missing, corrupt, or oversized images are reported, and remote-only references are not downloaded. Re-encoding does not copy source EXIF/GPS metadata; image pixels are not automatically masked. Text redaction and recoverable backups retain their separate behavior.

### Raw session backup

`.codexmonitorbundle` uses the `codex-notch-session/v1` format and contains:

- Manifest and format version.
- SHA-256 for every included file.
- Active/archive state.
- Project path and reliably observed account alias.
- Raw JSONL.

Before import, the app rejects zip-slip paths, symlinks, invalid manifests, checksum mismatches, internal ID mismatches, and missing project paths that were not remapped. Duplicate IDs are skipped by default, or the user can explicitly generate a new ID as a copy. The app creates a transaction backup before writing and reports local-file state and App Server visibility separately afterward.

### Full project transfer

A full project transfer bundle may include project files, a Git worktree, and related sessions. Import supports:

- Preflight validation before any overwrite.
- Manual mapping for missing directories.
- Exclusion of deployment packages, archives, large generated files, and obvious sensitive files.
- Blocking empty-project creation when all session IDs conflict.
- Importing only sessions without overwriting project files.
- Transaction-backup rollback after failure.

Run recovery or cleanup only after Codex has fully quit, so a running Codex process cannot write an older in-memory index over the newly restored state.

## Local files and network requests

### Main local paths

| Path | Default behavior | When the app writes |
|---|---|---|
| `~/.codex/sessions/` | Reads structured sessions and token events | Only during user-initiated import or recovery |
| `~/.codex/archived_sessions/` | Reads archived sessions and token events | Only during user-initiated import or recovery |
| `~/.codex/hooks.json` | Read-only during environment checks | After user confirmation to install, update, or uninstall Hooks; backed up first |
| `~/Library/Application Support/CodexNotchMonitor/events/` | Consumes local Hook events | Hook Helper writes small event files |
| `~/Library/Application Support/CodexNotchMonitor/account-continuity.json` | Stores local account-continuity evidence | When a reliable account transition or session attribution is observed |
| `~/Library/Application Support/CodexNotchMonitor/quota-reset-state.json` | Stores quota snapshots, pending verification, and recovery history | When reliable quota changes are observed |
| `~/Library/Application Support/CodexNotchMonitor/continuity-backups/` | Stores transaction backups for import, recovery, and cleanup | Before a corresponding user-initiated write operation |
| `~/Library/Application Support/CodexNotchMonitor/setup-backups/` | Stores Hook configuration and Helper backups | Before user-confirmed Hook install, update, or uninstall |
| `~/Library/Caches/com.coverai.codex-notch-monitor/model-prices.json` | Stores the validated model-price catalog | After a successful price refresh |

### External network requests

| Destination | Purpose | Carries local statistics? |
|---|---|---|
| Local Codex App Server process | Account, quota, and state-database visibility | Local IPC, not a public network request |
| `codex-reset.com` | Feed, timeline, and forecasts | No |
| `developers.openai.com` | Public official Standard pricing table; no API key | No |
| `ericjypark.github.io` | Public model-price catalog | No |
| `api.github.com` | Daily or manual Codex Monitor Latest Release check | No |
| `coverai.store` | Website link opened by the user | Only after a click; no local data appended |
| `x.com` | Original evidence opened by the user | Only after a click |

## Development, testing, and builds

### Run the full test suite

The full test suite keeps fixture panels hidden by default. Run `CODEX_ISLAND_VISIBLE_QA=1 zsh scripts/test.sh` to briefly show an independent sample-data panel and check WindowServer visibility, scroll playback, interrupted transitions, and focus preservation. It does not create real Codex tasks or change Hook configuration.

```bash
./scripts/test.sh
```

The script covers:

- App Server model parsing, quota windows, and menu bar quota ring.
- Fixed Ripple Glow, three full-card Metal effects, completion/confirmation feedback and Activity Island lifecycle.
- Activity Island preferences and layout state.
- First-run setup, Hook merge, path quoting, review state, and connection state.
- GitHub Release decoding, version comparison, architecture matching, asset and SHA-256 validation, check cadence, and notification deduplication.
- Usage/Cost scan, account attribution, project aliases, activity heatmap, and price catalog.
- Tibo/Codex Reset Radar decoding, source validation, cache, and timeline.
- Three reset categories, pending verification, user display type, and notification evidence.
- Session continuity, export, import, full project transfer, deletion queues, backup, and rollback.
- Python Hook install/uninstall scripts.

### Architecture and signature verification

```bash
lipo -archs build/CodexNotchMonitor.app/Contents/MacOS/CodexNotchMonitor
lipo -archs build/CodexNotchMonitor.app/Contents/Helpers/CodexMonitorHook
codesign --verify --deep --strict build/CodexNotchMonitor.app
```

Both binaries in a Universal build should contain `arm64` and `x86_64`.

### Main source layout

```text
Sources/CodexNotchMonitor/
  App.swift                         App lifecycle and window orchestration
  GlanceView.swift                  Menu bar overview panel
  NotchView.swift                   Main Monitor Center pages
  MonitorStore.swift                Data refresh, state composition, and operations
  QuotaService.swift                Codex App Server quota and reset credit
  CostService.swift                 Local Usage/Cost log scan and aggregation
  PricingCatalog.swift              Public model-price catalog and cache
  CodexResetRadarService.swift       codex-reset.com feed/timeline/forecast
  QuotaResetMonitor.swift            Recovery evidence and three reset categories
  SessionContinuityService.swift     Local session inventory and App Server visibility
  SessionExportService.swift         Markdown/HTML/session-bundle export
  SessionExportImages.swift          Readable-export image recovery and assets
  SessionImportService.swift         Session-bundle preflight, import, backup, and rollback
  ProjectTransferService.swift       Full project transfer
  CodexSetupService.swift            First-run setup, Hook installation, and review state
  SetupPermissionsView.swift         Setup & Permissions UI
  ActivityIslandView.swift           Floating Activity Island view
  ActivityIslandWindowController.swift
                                     Floating island window and lifecycle

Sources/CodexMonitorHook/
  main.swift                          Minimal local Hook Relay Helper

Tests/                                Focused Swift and Python tests
scripts/                              Test, build, install, and Hook scripts
Resources/                            Info.plist, fonts, logo, and shaders
docs/images/                          Current real UI screenshots for README
```

## FAQ

### Quota shows `--%` or keeps failing to refresh

This usually means the local Codex App Server is unavailable, signed out, or timed out. The app preserves the latest successful value and retries with backoff. Confirm that Codex is running and signed in, then refresh. `--%` does not mean zero quota.

### Usage/Cost looks empty for another account

Choose the account under Statistical Scope in Monitor Center and confirm the current period. The app assigns sessions only when reliable evidence exists. History from before first observation, or created during an offline account switch, remains Unattributed instead of being guessed into an account.

### The app still says “Waiting for first real message” after security review

1. Use `Cmd + Q` to quit Codex completely instead of closing only the window.
2. Reopen Codex and send a normal user message.
3. Return to Setup & Permissions and refresh.
4. If the state changes to Hook Update Required, use the in-app flow to back up and update, then complete security review again.
5. Do not open multiple review terminals or manufacture a test session to bypass real-event verification.

“Security review complete” and “Connected” are separate states. The first confirms that the user approved the current Hook definition; the second requires a real event from the current Helper installation.

### Dynamic Center shows old data or “Data may be delayed”

Dynamic Center depends on the third-party `codex-reset.com` service. If the network fails, upstream data is delayed, or response validation fails, the app keeps the latest valid cache. Use the Official Quota card and original X links as evidence and never treat forecast percentages as official commitments.

### A model appears as unknown or `$0` in Cost

The model may not yet exist in the public price catalog, or it may be an internal route without a verifiable public price. The app does not invent a price for unknown models, so they contribute `$0` and remain listed in the source card.

GPT-6 Astra, GPT-6.1 Sol, GPT-6 Sol, GPT-6 Luna, and the GPT-5.6 family prefer the latest successfully synchronized official Standard rates, falling back to the verified embedded snapshot; the third-party catalog cannot override them. Above 272K input tokens, input and cache rates use a 2x multiplier and output uses 1.5x. Tool fees, Fast mode, and Batch/Flex discounts are outside this standard estimate.

### Are Hooks required?

No. Official quota, Usage, Cost, Dynamic Center, and most local session inventory work without Hooks. Hooks mainly add live lifecycle phases, especially tool use and approval waits.

### Why is a session file present but still missing from the Codex sidebar?

Local JSONL presence, App Server indexing, and Codex UI visibility are three different stages. Session Management reports them separately. If necessary, fully quit Codex before recovery and use the App Server visibility check. Do not equate “file copied” with “session restored.”

## Known limitations

- App Server reports quota-window usage percentages and reset times, not a fixed number of remaining messages.
- A separately launched App Server process may not see in-memory tasks from another running Codex Desktop process. The app complements it with Hooks and local structured records.
- Account attribution uses evidence observed after the feature is enabled. Baseline history and sessions created during an offline account switch may remain Unattributed.
- If API-key sign-in does not expose a stable account identifier, the app cannot reliably distinguish two different keys and will not claim that a switch was detected.
- The app currently processes Codex local logs only; it does not scan Claude or OpenCode logs.
- Dynamic Center is not an official OpenAI source. Tibo posts and community probabilities are supporting evidence only.
- Cost is not a bill. Public model-price changes affect estimates, and unknown models count as `$0`.
- Raw session and project-transfer bundles contain sensitive content and are not suitable for public sharing.
- The app currently uses an ad-hoc signature and has no Developer ID notarization or automatic update signature. GitHub Releases provide manual downloads.
- The update checker opens the matching DMG or Release download URL only; it never mounts an image, replaces the app, or requests administrator privileges automatically.

## Official protocol references

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)

## Credits and acknowledgements

- Cost semantics, `last_token_usage` handling, API-equivalent estimation, and parts of the interaction language were informed by the MIT-licensed [ericjypark/codex-island](https://github.com/ericjypark/codex-island) project.
- Dynamic Center reads the public aggregation API from [codex-reset.com](https://codex-reset.com/zh/tibo), which is not an official OpenAI service.
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components and license notices.
- Task cards, fixed-canvas native transitions, pointer routing, and scroll anchors are adapted from [QuotaView f632288](https://github.com/Duoasa/QuotaView/tree/f632288fb706b83e691000e365004f6ed9654d94). The full MIT notice is bundled at `Contents/Resources/ThirdPartyNotices.txt`.

## License

This project is licensed under the [MIT License](LICENSE), Copyright (c) 2026 CoverAI. You may use, copy, modify, merge, publish, distribute, sublicense, or sell the Software as long as the copyright and permission notices are retained. The Software is provided “as is,” without warranty of any kind.

Monitor Center activity heatmaps follow the summary period by default, with an optional independent range. Token totals include cache; input labels exclude cache. Menu settings hide task density and overflow until task display is enabled; legacy Detailed preferences remain readable and map to Automatic in the settings UI. Hook configuration remains in a collapsed advanced section and does not resume paused Hook ingestion.

Activity bars and heatmap cells share a cyan fill palette, corner radius, subtle outline, neutral zero state, and immediate hover feedback. Readouts occupy the same upper-right position; cost readouts include corresponding tokens. Range changes crossfade and respect Reduce Motion.

Usage and Cost share a compact account/period toolbar, sliding period indicator, white primary metrics, layered neutral cards and cyan charts. Equal-period line/area coordinates interpolate; period or point-count changes crossfade. Bars and heatmap colors animate incoming values, and project rows share hover, press and expansion feedback. Scope explanations remain available through an accessible information popover.

Trend lines and areas share monotone cubic interpolation through the actual samples, with bounded controls to avoid overshoot. Readouts remain above the plot. Seven-day activity uses capped-width vertical columns, one date per column, and full-column hit regions; zero values stay empty. Period button hover and selection layers share slot geometry with only the outer three-point inset.
