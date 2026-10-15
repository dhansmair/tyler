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

- **Tiling** of every window into an ordered list. Provides basic layouts out of the box: `tall`, `grid`, `full`.
  See [Layouts](docs/layouts.md).
- **Several displays**, each with its own row of workspaces. Windows can be dragged across, and
  displays that come and go are followed.
- **Mouse Support** resize tiled windows and the layout follows; drag a window onto another to swap
  them; Option-drag anywhere in a window to move or resize it.
- **Swipe Gestures** swipe with three fingers to switch between workspaces
- **Menu bar indicators** shows the workspaces as numbers or as a small map of every workspace and its
  windows.
- **A config file** for gaps, the number of workspaces, layouts, app assignments, gestures and the
  mouse, applied with `tyler config reload`; `tyler config set` tries a setting out until tylerd
  stops.
- **Rich CLI Commands** Tyler doesn't integrate keybindings natively, but provides various commands 
  that can be bound to keyboard shortcuts, e.g. via `skhd`.
- **Animations** window swapping, resizing, closing or moving between workspaces can be animated.
- **No SIP changes.** tyler uses only the public Accessibility API: no private APIs, no scripting
  additions, System Integrity Protection stays on.

See [Features](docs/features.md) for the details.

### Workspace Indicators
<img width="310" height="34" alt="image" src="https://github.com/user-attachments/assets/c031ff86-a4e3-4fa3-9488-6656dc0749dd" />

### Demo Video
https://github.com/user-attachments/assets/5a3979a9-e80c-4d72-8321-f3b1b17f5d9e

## Requirements

- macOS 14 or later. Only macOS 26 on an Apple silicon Mac has been tried so far.
- The Xcode Command Line Tools with Swift 6 (`xcode-select --install`). Full Xcode works too but
  isn't needed.
- Accessibility permission for the terminal you start tyler from.

## Installation

There is no `brew` package or similar yet; tyler must be installed from source:

```bash
git clone https://github.com/dhansmair/tyler.git
cd tyler
make install          # builds a release and copies tyler and tylerd to ~/.local/bin
```

Add `~/.local/bin` to your `PATH` if it isn't there yet (for zsh, in `~/.zshrc`:
`export PATH="$HOME/.local/bin:$PATH"`). `make install PREFIX=/some/dir` installs elsewhere.

Then start it:

```bash
tyler start
```

> [!IMPORTANT]
> `tylerd`, the server, now runs in the background and keeps running when you close the terminal. It
> needs Accessibility permission, which macOS gives to the app that started it: open System Settings >
> Privacy & Security > Accessibility and turn on your terminal. `tylerd` notices within a second and
> tiles your windows. `tyler status` shows that it runs; `tyler window list` shows the windows it
> tiles.

### Updating

```bash
git pull
make install
tyler restart         # windows stay where they are
```

### Starting at login

There is no login service yet. Run `tyler start` from your terminal after logging in, or let your
shell do it, for example in `~/.zprofile`:

```bash
tyler start >/dev/null 2>&1   # does nothing if tylerd already runs
```

Start it from the terminal app that has the Accessibility permission.

### Uninstalling

```bash
tyler stop                                   # puts every window back
rm ~/.local/bin/tyler ~/.local/bin/tylerd
rm -r ~/.tyler ~/.config/tyler               # the socket, log and config
```

Then remove your terminal from the Accessibility list if nothing else needs it.

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
