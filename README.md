# Tyler

A dynamic tiling window manager for macOS with an XMonad-style layout system.
Windows are ordered in a flat list. Tyler offers basic layouts (tall, grid, full)
and supports animations, mouse events and trackpad gestures.

> [!WARNING]
> **tyler is alpha software.**
> Expect bugs, and expect commands and settings to change before 1.0.
>
> **It is almost entirely written by [Claude Code](https://claude.com/claude-code)**,
> with a human deciding what to build, trying it on real windows and reviewing the result. The code
> is unit tested and linted, but no human has read every line. [`CLAUDE.md`](CLAUDE.md) and
> [`devdocs/`](devdocs) show how it is built.

## Features

- **Tiling**: Provides basic layouts out of the box: `tall`, `grid`, `full`.
  See [Layouts](docs/layouts.md).
- **Animations**: window swapping, resizing, closing or moving between workspaces can be animated.
- **Several displays**: each with its own row of workspaces. Windows can be dragged across, and
  displays that come and go are followed.
- **Mouse Support**: resize tiled windows and the layout follows; drag a window onto another to swap
  them; Option-drag anywhere in a window to move or resize it.
- **Swipe Gestures**: swipe with three fingers to switch between workspaces
- **Menu bar indicators**: shows the workspaces as numbers or as a small map of every workspace and its
  windows.
- **No SIP changes.** tyler uses only the public Accessibility API: no private APIs, no scripting
  additions, System Integrity Protection stays on.

See [Features](docs/features.md) for the details.

### Demo

https://github.com/user-attachments/assets/d168cf84-ab63-4a10-8923-fb79e0c58f3d

### Workspace Indicators
<img width="310" height="34" alt="image" src="https://github.com/user-attachments/assets/c031ff86-a4e3-4fa3-9488-6656dc0749dd" />

## Requirements

- macOS 14 or later. Only macOS 26 on an Apple silicon Mac has been tried so far.
- The Xcode Command Line Tools with Swift 6 (`xcode-select --install`). Full Xcode works too but
  isn't needed.
- Accessibility permission for `Tyler.app`, which macOS asks for when tyler first starts.

## Installation

With [Homebrew](https://brew.sh), from the tap
[dhansmair/homebrew-tyler](https://github.com/dhansmair/homebrew-tyler):

```bash
brew install dhansmair/tyler/tyler   # builds the latest release from source, about a minute
```

`tyler@<version>` stays at one release, and `--HEAD` builds `main` (see the tap's README). To
build it yourself, see [Installing from source](docs/install-from-source.md).

`Tyler.app` comes with it: `tylerd` runs as an app with its own Accessibility permission (see the
[manual](docs/manual.md#running-tylerd)), and `tyler start` copies it into `~/Applications`, so you
can also start it from Spotlight. The app is signed ad hoc, and macOS treats every update as a new
app: it asks for the permission again after each one.

Then start it:

```bash
tyler start
```

> [!IMPORTANT]
> `tylerd`, the server, now runs in the background as `Tyler.app` and keeps running when you close
> the terminal. It needs Accessibility permission: macOS asks, and System Settings > Privacy &
> Security > Accessibility lists `Tyler.app`; turn it on. `tylerd` tiles your windows once it
> notices (if it doesn't within a few seconds, run `tyler restart`). `tyler status` shows that it
> runs; `tyler window list` shows the windows it tiles.

### Updating

```bash
brew upgrade tyler
tyler restart         # windows stay where they are
```

The new build needs the permission again: `tyler restart` puts every window back where it was,
resets the old entry in System Settings, and macOS asks; once you turn `Tyler.app` on, the windows
go back to their workspaces.

### Starting at login

There is no login service yet. Run `tyler start` from your terminal after logging in, or let your
shell do it, for example in `~/.zprofile`:

```bash
tyler start >/dev/null 2>&1   # does nothing if tylerd already runs
```

### Uninstalling

```bash
tyler stop                                   # puts every window back
tccutil reset Accessibility io.github.dhansmair.tyler   # Tyler.app's permission
brew uninstall tyler
rm -r ~/Applications/Tyler.app
rm -r ~/.tyler ~/.config/tyler               # the socket, log and config
```

Reset the permission before deleting the app: `tccutil` only finds an app that is still there.

## Keybindings

tyler has no hotkeys of its own: every action is a `tyler` command, and you bind keys to them with
[skhd](https://github.com/koekeishiya/skhd),
[Karabiner-Elements](https://karabiner-elements.pqrs.org) or [Raycast](https://www.raycast.com).
With skhd, for example:

```
alt - j : ~/.local/bin/tyler window focus next
alt - k : ~/.local/bin/tyler window focus prev
alt - return : ~/.local/bin/tyler window swap master
alt - 1 : ~/.local/bin/tyler workspace focus 1
alt + shift - 1 : ~/.local/bin/tyler window move-to-workspace 1
```

[Keybindings](docs/keybindings.md) has a full suggested set for all three tools.

## Configuration

tyler reads `~/.config/tyler/tyler.toml`. The file is optional; every setting has a default. After
editing it, run `tyler config reload`. [`docs/tyler.toml`](docs/tyler.toml) is a sample with every
setting at its default and a comment each, to copy and edit; the
[manual](docs/manual.md#configuration) explains every setting.

```toml
[gaps]
inner = 8
outer = 8

[mouse]
focus-follows = true

[apps.Firefox]
workspace = 2
```

## Documentation

- [Manual](docs/manual.md): concepts, running tylerd, the config file, every command
- [Layouts](docs/layouts.md) and [Features](docs/features.md)
- [Keybindings](docs/keybindings.md) and [Troubleshooting](docs/troubleshooting.md)
- [Known issues](docs/known-issues.md) and the [changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md), and how tyler is built: [`CLAUDE.md`](CLAUDE.md),
  [`devdocs/design.md`](devdocs/design.md)

## License

[MIT](LICENSE)
