# Nehir

A scrolling tiling window manager for macOS, built on the Niri column layout paradigm.

> **Nehir** (Turkish for "river") — windows flow in columns, scrolling horizontally across your screen.

## Features

- **Niri scrolling column layout** — windows arranged in columns that scroll horizontally
- **Workspace management** — multiple workspaces with hotkey switching
- **Window borders** — configurable colored borders on the focused window
- **Workspace bar** — per-monitor status bar showing workspace names and app icons
- **Focus follows mouse** — optional hover focus
- **Multi-monitor support** — seamless window management across displays
- **Overview mode** — bird's-eye view of all windows
- **Quake terminal** — drop-down terminal with Ghostty integration
- **Command palette** — fuzzy search for commands
- **App rules** — per-application layout overrides
- **IPC** — Unix socket for external control via `nehirctl`
- **TOML configuration** — `~/.config/nehir/settings.toml`

## Install

```bash
swift build -c release
cp .build/release/Nehir /usr/local/bin/
cp .build/release/nehirctl /usr/local/bin/
```

Or use mise:

```bash
mise run install
```

## Usage

```bash
# Run
Nehir

# CLI control (requires IPC enabled)
nehirctl focus left
nehirctl switch-workspace 2
nehirctl --help
```

## Configuration

Config file: `~/.config/nehir/settings.toml`

### Default Modifier

The default modifier key is **⌘⌥ (Cmd+Option)**. Change it in the Nehir menu → Settings → Hotkeys → Nehir Modifier.

## Development

```bash
# Build (debug)
mise run build

# Build and run
mise run dev

# Release build
mise run build:release

# Run tests (requires Xcode)
mise run test

# Clean
mise run clean
```

## Forked from OmniWM

Nehir is a focused fork of [OmniWM](https://github.com/BarutSRB/OmniWM), stripped down to a single layout engine (Niri scrolling columns) with simplified controls.

**Changes from upstream:**
- Removed Dwindle (BSP) layout engine and all multi-layout switching
- Removed hotkey presets (Vim navigation, Caps Lock modifier)
- Removed leader key / sequence hotkey support
- Removed update checker and update notification window
- Changed default modifier from Option to Cmd+Option (avoids macOS text editing conflicts)
- Renamed all internal "Hyper" terminology to "Modifier"
- Simplified hotkey settings UI
- Added git commit hash display in debug builds
- Added mise task configuration for build/dev/test/install

## License

GPL-2.0-only
