<div align="center">

<img src="Resources/Pulse-Logo.svg" alt="Codex Pulse logo" width="72">

# Codex Pulse

**Keep track of Codex and Claude Code quotas, tasks, and usage from your menu bar and notch.**

[简体中文](README.md) · [Download v1.10.0](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.10.0) · [MIT License](LICENSE)

macOS 13+ · Native SwiftUI / AppKit · Apple Silicon / Intel

</div>

## What it does

Codex Pulse is a native macOS menu bar app with three entry points:

- **Dynamic Island in the notch**: follow running tasks;
- **Glass menu bar panel**: check quotas at a glance;
- **Monitor Center**: explore usage, costs, and sessions in detail.

All data comes from your Mac: the Codex App Server, desktop IPC, and local session logs. No account credentials are read.

### Dynamic Island

- **Fast mode**: Expanded cards show “Fast” alongside model details only when explicitly enabled; disabled or unknown states show no label. Claude uses its session status line’s `fast_mode`; Codex reads owned `thread_settings_applied` checkpoints and explicit per-turn tiers, including Codex CLI sessions in One. Missing evidence shows no label; global defaults are not treated as session evidence. Hidden in privacy mode.

- **In-island Clawd**: compact mode places Clawd and quota on the left, with task status and ×N for concurrent tasks on the right. Animation uses cached frames; card portraits are static and gaze is fixed. The outline breathes while awaiting approval or a reply, and flashes once on completion or failure. Supports hiding Clawd, three sizes, and Reduce Motion.
- **Hardware black shell**: the island matches the notch, with concave top corners that blend into the menu bar. A thin edge light follows the task state, with adjustable intensity in settings.
- **Focus stage**: the expanded island shows a single focus card with up to 3 steps and Token usage for this turn, prioritizing running or waiting calls. Codex and Claude share status labels, colors, and node rules; task endings preserve known outcomes and mark unresolved calls gray. Other sessions appear as a row of capsules; click one to switch. New approval or reply requests automatically take focus. Three seconds after a task finishes, focus moves to a task that is still running. Ended sessions remain in the list for 1 minute. Collapsing pauses expanded-card animations while preserving answer drafts for reopening; see [focus stage](docs/island-focus-stage.md).
- **Reset-card expiry reminders**: available quota reset cards trigger system and island notifications at 24, 12, and 6 hours before expiry, once per card and stage. Enabled by default under Setup & Permissions. Checks run with successful minute-by-minute quota refreshes while the app is running; reopening catches up only the most urgent missed stage. Used or expired cards are excluded.
- **In-island approval**: explicitly approve or answer questions for requests currently waiting in Codex or Claude Code. Claude Code questions support single choice, multiple selections, custom text, and option descriptions. Other requests return to the original client; nothing is approved automatically.
- **Motion effects**: retain three Metal progress effects (state smoke, quantum noise, and liquid waves), plus completion confetti and confirmation pulses. All become static when Reduce Motion is enabled.

- **Alerts and completion feedback**: Followed signals and quota recovery appear as system notifications and island cards. Alerts use the configured expanded width and fit their height to the content. They pause on hover and yield to approvals and completion celebrations. Choose from three confetti levels and five completion sounds.
- **Text answers**: Answer Codex questions with free text, including Chinese input methods. Unanswered asynchronous questions remain visible after the turn ends; replies after completion start a turn in the same conversation with inherited settings, and success requires a valid response plus the actual answer in an authoritative snapshot.
- **Notification settings**: Request notification permission when needed, send a sound-enabled test notification, and preview number formatting using current-account usage.

### Glass menu bar panel

- **Forecast area**: large rounded numerals show the remaining percentage of the quota window that is the bottleneck. A forecast based on this cycle's consumption rate indicates whether it will last until reset or roughly when it will run out, explicitly labeled as an estimate. Panel colors follow quota availability: cool cyan when plentiful, amber when tight, and red when critical.
- **Codex / Claude switching**: once Claude Code integration is enabled, switch between the two sources in the header. Claude shows 5-hour and weekly quotas.
- **7-day strip**: the heading itself switches between Cost and Token. Only weekdays appear below the bars, with values collected in a single row underneath. Days with unpriced models are labeled “Amount unknown.”
- **Glass appearance**: retain liquid glass effects, with Panel Opacity applied to the entire panel. Reduce Transparency or Increase Contrast automatically switches it to an opaque appearance.

### Monitor Center

- **Usage and costs**: view Token usage, caches, project rankings, and trends by period. Costs are estimated using public model prices: API-equivalent amounts, not subscription bills. Official Standard synchronization accepts the current and legacy table formats, uses the 30-minute cache-write rate, and retains the last valid prices on failure.
- **Activity Center**: brings together official quotas, community updates, reset timelines, and local recovery records, with each source clearly identified.
- **Session management**: search projects and sessions, inspect account ownership and exception summaries, and export Markdown / HTML, create raw backups, import, or migrate projects. The inventory caches metadata and short titles; full-text exports still read the original logs.
- **Claude Code**: separate connection controls, permission requests, official quotas, and local Token and cost history. The island shows the latest public progress text for the current turn alongside real tool steps, including Bash command descriptions, with running, waiting, success, failure, and ended states; up to three nodes prioritize calls still running or waiting. After the monitor restarts, verified busy sessions are recovered from Claude’s local registry; idle windows do not count as active tasks.

### Number units

Large numbers use Chinese 万 (ten thousand) / 亿 (hundred million) units by default, for example `8,432`, `541万`, and `1.84亿`. Switch to K / M / B under “Menu Bar & Panel → Content → Usage → Number Units.” Amounts, percentages, and session counts are unaffected.

## Interface previews

### Dynamic Island

<p align="center">
  <img src="docs/images/pulse-island-focus.png" alt="Expanded Dynamic Island: hardware black shell, state edge light, glowing eye focus card, and session capsules" width="90%">
</p>

### Glass menu bar panel

<p align="center">
  <img src="docs/images/pulse-glance.png" alt="Glass panel: Codex on the left (remaining quota, consumption forecast, and 7-day costs), Claude on the right (weekly and 5-hour quotas)" width="72%">
</p>

### Monitor Center

<p align="center">
  <img src="docs/images/pulse-usage.png" alt="Usage analysis: Token overview, trends, activity, and project rankings" width="49%">
  <img src="docs/images/pulse-cost.png" alt="Cost estimates: API-equivalent costs and trends" width="49%">
</p>
<p align="center">
  <img src="docs/images/pulse-dynamic-center.png" alt="Activity Center: official quotas, community predictions, and public updates" width="49%">
  <img src="docs/images/pulse-sessions.png" alt="Session management: project summaries, update times, and account ownership" width="49%">
</p>
<p align="center">
  <img src="docs/images/pulse-claude-code.png" alt="Claude Code: connection controls, official quotas, and local usage" width="49%">
</p>

### Settings

<p align="center">
  <img src="docs/images/pulse-island-settings.png" alt="Dynamic Island settings: live preview, edge light intensity, and automatic expansion" width="49%">
  <img src="docs/images/pulse-panel-settings.png" alt="Menu bar and panel settings: live panel preview, content toggles, and number units" width="49%">
</p>

<details>
<summary>Installation & Permissions</summary>
<p align="center">
  <img src="docs/images/pulse-setup.png" alt="Installation & Permissions" width="82%">
</p>

</details>

## Download and install

Current source and local build: **v1.11.0 (Build 33)**. Latest public release: **v1.10.0**. Download the installer for your Mac from [GitHub Releases](https://github.com/suguxiaojie/codex-pulse/releases/tag/v1.10.0):

| Mac processor | Installer |
|---|---|
| Apple Silicon (M series) | [arm64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.10.0/CodexNotchMonitor-v1.10.0-arm64.dmg) |
| Intel | [x86_64 DMG](https://github.com/suguxiaojie/codex-pulse/releases/download/v1.10.0/CodexNotchMonitor-v1.10.0-x86_64.dmg) |

1. Open the DMG and drag the app into Applications.
2. Launch the app. Make sure Codex / ChatGPT Desktop is installed and signed in.
3. Enable notifications if needed. Check the task-monitoring connection under Installation & Permissions.

The app uses an ad-hoc signature and has not been notarized by Apple. If macOS blocks the first launch, verify the download source, then allow it in System Settings → Privacy & Security.

The app was renamed from Codex Monitor. Its Bundle ID, `CodexNotchMonitor.app` filename, preferences, and data directories retain their original values, so existing settings and data remain available after upgrading. The in-app Check for Updates action only opens the download page; you install updates yourself.

## Data sources and boundaries

| Content | Source and explanation |
|---|---|
| Official quotas and account | Local Codex App Server; shows quota percentages and reset times, not remaining message counts |
| Quota forecast | Extrapolated from the current window's used percentage and elapsed time; an estimate only, with no forecast during the first hour of a cycle |
| Token and project statistics | Local structured session logs, including caches; covers only history still readable on this Mac |
| Live tasks | Codex uses desktop IPC and local logs; Claude Code uses optional dedicated Hooks, transcripts, process fallback, and its local live-session registry at startup |
| Costs | Token × public model prices; API-equivalent estimates, **not subscription bills**; unknown prices are explicitly marked |
| Community updates and predictions | Third-party aggregator [codex-reset.com](https://codex-reset.com/zh/tibo); predictions do not guarantee a reset for your account |
| Session account ownership | Uses only reliably observed evidence; records predating the baseline or lacking evidence remain “Unassigned” |

- Does not read `auth.json`, cookies, API keys, Claude credentials, or Keychain. Local sessions, projects, and usage are not uploaded to community sources or price catalogs.
- Codex task monitoring installs no Hooks and does not write Codex client configuration. Claude Code integration is disabled by default. Before enabling it, the app backs up `settings.json` and manages only its own entries. Disabling it restores the original status line and preserves other tools' configuration.
- Import, recovery, deletion, migration, and manual quota resets are initiated by you, with their scope shown before execution. Quota resets require a second confirmation.
- Readable exports redact sensitive body text by default. Raw backups and migration packages may contain source code, prompts, and attachments; keep them secure yourself.

## Build from source

Requires the Swift 6 toolchain and macOS build tools, with no third-party Swift Package dependencies.

```bash
git clone https://github.com/suguxiaojie/codex-pulse.git
cd codex-pulse
./scripts/build-app.sh native        # Build for the current architecture
open build/CodexNotchMonitor.app
```

```bash
./scripts/test.sh                    # Full tests (including Claude integration tests)
./scripts/build-dmg.sh arm64         # Apple Silicon installer
./scripts/build-dmg.sh x86_64        # Intel installer
```

More documentation:

- [In-island approvals](docs/island-approvals.md)
- [Claude Code integration](docs/claude-code-integration.md)
- [Reading compressed session history](docs/compressed-rollouts.md)
- [Project roadmap](ROADMAP.md)

## Acknowledgments and license

Thanks to [Codex Island](https://github.com/ericjypark/codex-island), [QuotaView](https://github.com/Duoasa/QuotaView), and [Open Claude UI](https://github.com/Caho1/open-claude-ui). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party sources and complete licenses.

This project is licensed under the [MIT License](LICENSE), Copyright (c) 2026 CoverAI. Codex Pulse is an independent project with no official affiliation with OpenAI or Anthropic.

Support the project: [CoverAI's top-up service](https://www.coverai.store/).
