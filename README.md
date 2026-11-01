<p align="center">
  <img src="docs/assets/logo.png" alt="LidAwake" width="128">
</p>

<h1 align="center">LidAwake</h1>

<p align="center">
  <a href="https://github.com/habibtalib/lidawake/actions/workflows/ci.yml"><img src="https://github.com/habibtalib/lidawake/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-1B2238?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10-E5483A?logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/MCP-server-FF8A4C" alt="MCP server">
  <img src="https://img.shields.io/badge/dependencies-zero-2A9D8F" alt="Zero dependencies">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-1B2238" alt="MIT License"></a>
</p>

<p align="center">
  <b>Keep your MacBook awake with the lid closed.</b><br>
  A menu bar switch, a desktop widget, a CLI and an MCP server for <code>sudo pmset -a disablesleep 1</code>,<br>
  with an auto-off timer and a battery guard so you never forget it on.
</p>

<p align="center">
  <a href="#-install">Install</a> ·
  <a href="#-features">Features</a> ·
  <a href="#-agent-mode">Agent mode</a> ·
  <a href="#-desktop-widget">Widget</a> ·
  <a href="#-cli">CLI</a> ·
  <a href="#-mcp-server">MCP</a> ·
  <a href="#-security">Security</a>
</p>

---

<p align="center">
  <img src="docs/assets/panel-dark.png" alt="LidAwake menu bar panel, dark" width="320">
  &nbsp;
  <img src="docs/assets/panel-light.png" alt="LidAwake menu bar panel, light" width="320">
</p>

## 💡 Why

Closing a MacBook's lid puts it to sleep, unless an external display, keyboard and power are all connected. That kills SSH sessions, long builds, downloads, agent runs and music over AirPlay.

`sudo pmset -a disablesleep 1` stops that, but it needs a password every time, it is easy to forget, and a Mac left awake in a bag gets hot and drains the battery. LidAwake turns it into a one-click switch that turns itself off.

## ✨ Features

- **Menu bar switch.** A big power button with a live countdown ring. The menu bar icon shows the state and the time left.
- **Extend in one click.** +30m and +1h while a timer runs, or drag the custom slider (15 minutes to 12 hours).
- **Timer.** Keep awake for 30 minutes, 1, 2 or 4 hours, or until you turn it off.
- **Battery guard.** Sleep comes back on automatically when you are on battery at 10, 20 or 30% or below.
- **Desktop widget.** Small and medium sizes with interactive buttons (macOS 14+).
- **CLI.** `lidawake on --for 2h`, `lidawake off`, `lidawake status --json`.
- **MCP server.** Lets Claude Code and other agents keep the Mac awake for long tasks, then switch it back.
- **No password prompts.** One admin prompt installs a sudoers rule that allows only `pmset -a disablesleep 1` and `0`.
- **Agent mode.** Turns on by itself while Claude Code is working and lets the Mac sleep once it goes quiet.
- **Auto-off.** Sleep comes back on after agents are quiet, the Mac is idle, or the network is down for too long.
- **Safe quit.** Quitting while awake asks whether to turn sleep back on.
- **Zero dependencies.** Swift, SwiftUI, WidgetKit and IOKit only.

## 📦 Install

Requires macOS 14 or later and the Xcode command line tools.

```bash
git clone https://github.com/habibtalib/lidawake.git
cd lidawake
Scripts/bundle-app.sh --install     # ~/Applications/LidAwake.app + ~/.local/bin/{lidawake,lidawake-mcp}
lidawake install-permission         # one admin prompt
open ~/Applications/LidAwake.app
```

Or click **Install Permission** in the menu bar panel instead of running `lidawake install-permission`. Turn on **Launch at login** in Settings so the timer and battery guard keep working after a restart.

<details>
<summary><b>Build with the desktop widget</b></summary>

Widgets need a team-signed app with an App Group. A free Personal Team works.

```bash
brew install xcodegen
LIDAWAKE_TEAM=<your team ID> Scripts/build-widgets.sh --install
```

Find your team ID in Xcode > Settings > Accounts. Then right-click the desktop > Edit Widgets > LidAwake.
</details>

## ⚙️ How it works

| Piece | What it does |
|---|---|
| `pmset -g` | Read the current `SleepDisabled` value. No root needed. |
| `/etc/sudoers.d/lidawake` | Lets your user run exactly `/usr/bin/pmset -a disablesleep 1` and `0` without a password. Validated with `visudo` before install. |
| `~/Library/Application Support/LidAwake/session.json` | The current session: when it started, the deadline, the battery floor and what started it. |
| Menu bar app | Checks every 30 seconds and on every power-source change. Turns sleep back on when the timer ends or the battery floor is reached, and posts a notification. |

The CLI and MCP server switch pmset directly. The timer and battery guard need the menu bar app running, or `lidawake on --for 2h --wait` in a terminal.

## 🤖 Agent mode

Turn on **Agent mode** in the panel (or `lidawake rules --agent-mode on`). LidAwake then keeps the Mac awake while
an agent is working and lets it sleep again once the agents have been quiet for 10 minutes. No timers to remember.

LidAwake knows an agent is working from three signals:

| Signal | Setup | How |
|---|---|---|
| Transcript writes | none | A Claude Code transcript in `~/.claude/projects` (or `$CLAUDE_CONFIG_DIR`, `~/.claude-profiles/*`) was written in the last 3 minutes. Only file times are read, never contents. |
| Claude Code hooks | `lidawake hooks install` | `UserPromptSubmit`/`PreToolUse` mark a session busy; `Stop`/`SessionEnd` mark it done. Your other hooks are left alone and `settings.json` is backed up first. |
| Keepalive | none | Any MCP agent calls `lidawake_keepalive {minutes, reason}`, or a script runs `lidawake keepalive 45m --reason "nightly build"`. |

### Auto-off rules

These apply to every session, including ones you started yourself. Change them in the panel or with `lidawake rules`:

| Rule | Default | Flag |
|---|---|---|
| Claude Code quiet | 15 min | `--agents-quiet 15m\|off` |
| No keyboard or mouse (and no agents) | 30 min | `--idle 30m\|off` |
| Network down | 10 min | `--network 10m\|off` |

A live keepalive always wins over these rules. The timer and battery guard always win over everything.

## 🧩 Desktop widget

The widget shows the state, a live countdown and the battery level. **Turn On / Turn Off** and the **30m / 1h / 2h** buttons work in place.

Widgets are sandboxed and cannot run `sudo`. A tap writes a small request to the shared App Group container and sends a Darwin notification. The menu bar app carries it out and refreshes the widget. If the app is not running, the widget shows **Open LidAwake**.

## ⌨️ CLI

```text
lidawake on [--for <duration>] [--battery-floor <percent>] [--wait]
lidawake off
lidawake toggle
lidawake status [--json]
lidawake keepalive <duration> [--reason <text>]
lidawake release [--reason <text>]
lidawake rules [--agent-mode on|off] [--agents-quiet <dur>|off] [--idle <dur>|off] [--network <dur>|off]
lidawake hooks install|uninstall|status
lidawake install-permission
lidawake uninstall-permission
lidawake version
```

```bash
lidawake on --for 1h30m --battery-floor 20
lidawake status
# ON: the Mac stays awake with the lid closed (1h 29m left).
# Turns off on battery at 20% or lower.
# Started from: cli.
# Battery: 64% (on battery).
```

## 🤖 MCP server

```bash
claude mcp add lidawake -s user -- $HOME/.local/bin/lidawake-mcp
```

| Tool | Arguments |
|---|---|
| `lidawake_status` | none |
| `lidawake_on` | `minutes?`, `battery_floor?`, `agent_mode?` |
| `lidawake_keepalive` | `minutes?` (default 30), `reason?` |
| `lidawake_release` | `reason?` (omit to release all) |
| `lidawake_off` | none |

Example: *"Hold the Mac awake while you run the migration, then release it."* The agent calls `lidawake_keepalive`, does the work, then `lidawake_release`.

## 🔒 Security

- The only command that runs as root is `/usr/bin/pmset -a disablesleep 1` or `0`. The sudoers rule names the full path and both exact argument lists, so no other arguments are allowed.
- The rule is written for your user only, and only after the user name passes a strict character check.
- The rule is checked with `visudo -c` before it is installed with mode `0440`, owner `root:wheel`.
- Remove it at any time: `lidawake uninstall-permission`, or delete `/etc/sudoers.d/lidawake`.

> **Heat warning:** a Mac running with the lid closed on battery, inside a bag or sleeve, can overheat. Use the battery guard and a timer.

## 🛠 Development

```bash
swift build
swift test
swift run LidAwakeApp
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License

[MIT](LICENSE) © 2026 Habib Talib
