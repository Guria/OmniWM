# Nehir

A scrolling tiling window manager for macOS, built on the Niri column layout paradigm.

> **Nehir** (Turkish for "river") — windows flow in columns, scrolling horizontally across your screen.

## Features

- **Niri scrolling column layout** — windows arranged in columns that scroll horizontally
- **Workspace management** — multiple workspaces with hotkey switching
- **Window borders** — configurable colored borders on the focused window
- **Workspace bar** — per-monitor status bar showing workspace names and app icons
- **Focus follows mouse** — optional X11-style hover focus
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

On first launch, settings are migrated from `~/.config/omniwm/settings.toml` if available.

## Development

```bash
# Build (debug)
mise run build

# Build and run
mise run dev

# Release build
mise run build:release

# Clean
mise run clean
```

## Forked from OmniWM

Nehir is a focused fork of [OmniWM](https://github.com/BarutSRB/OmniWM), stripped down to a single layout engine (Niri scrolling columns) with simplified controls.

**Removed from upstream:**
- Dwindle (BSP) layout engine
- Hotkey presets (Vim navigation, Caps Lock modifier)
- Leader key / sequence hotkey support
- Update checker
- Sponsor links

## License

GPL-2.0-only
