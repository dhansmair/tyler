# Tyler

Tyler is a dynamic tiling window manager for macOS. It arranges your windows using preset layouts,
and you can rearrange them with the keyboard or the mouse. It also supports animations and
trackpad gestures.

Why dynamic tiling? Because the mental model is extremely simple: each workspace is a single list of
windows, and you move windows up and down that list. I always found tree-based tilers too
complicated, since I rarely want more than two or three windows on a workspace.

> [!WARNING]
> **Tyler is alpha software.**
> Expect bugs, and expect commands and settings to change before 1.0.
>
> It is largely written by Claude Code,
> with a human deciding what to build, trying it on real windows and reviewing the result.
> [`CLAUDE.md`](CLAUDE.md) and [`devdocs/`](devdocs) show how it is built.

## Features

- Tiling: Provides basic layouts out of the box: `tall`, `grid`, `full`.
  See [Layouts](docs/layouts.md).
- Animations: window swapping, resizing, closing or moving between workspaces can be animated.
- Several displays: each display has its own workspaces.
- Mouse Support: resize tiled windows or drag a window onto another to swap them.
- Swipe Gestures: swipe with three fingers to switch between workspaces.
- Menu bar indicators: shows the workspaces as numbers or as a small map of every workspace and its
  windows.

- No SIP changes. Tyler moves windows through the public Accessibility API, with no scripting
  additions, so System Integrity Protection stays on. It uses private calls in two
  places: to read a window's ID and for the resize cursor over a gap.


See [Features](docs/features.md) for the details.

### Demo

https://github.com/user-attachments/assets/d168cf84-ab63-4a10-8923-fb79e0c58f3d

## Requirements

- macOS 14 or later. Only macOS 26 on an Apple silicon Mac has been tried so far.
- The Xcode Command Line Tools with Swift 6 (`xcode-select --install`)
- Accessibility permission for `Tyler.app`, which is requested on the first start.

## Installation

You can install tyler with [Homebrew](https://brew.sh):

```bash
brew install dhansmair/tyler/tyler        # builds the latest release
brew install dhansmair/tyler/tyler@v0.x.y # install specific version
brew install --HEAD dhansmair/tyler/tyler # builds from main
```

To build Tyler yourself, see [Installing from source](docs/install-from-source.md).

Installing adds `Tyler.app`, which runs `tylerd` in the background (see the [manual](docs/manual.md#running-tylerd)).

Then start it:

```bash
tyler start
```

> [!IMPORTANT]
> The daemon `tylerd` now runs in the background and keeps running when you close
> the terminal. It will prompt for Accessibility permission: System Settings > Privacy &
> Security > Accessibility lists `Tyler.app`; turn it on.
> Tyler tiles your windows once it notices (if it doesn't within a few seconds, run `tyler restart`).

Check the status:
```bash
tyler status
```

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

Tyler has no hotkeys of its own: every action is a `tyler` command, and you bind keys to them with
[skhd](https://github.com/koekeishiya/skhd),
[Karabiner-Elements](https://karabiner-elements.pqrs.org) or [Raycast](https://www.raycast.com).
With skhd, for example:

```
alt - j : tyler window focus next
alt - k : tyler window focus prev
alt - return : tyler window swap master
alt - 1 : tyler workspace focus 1
alt + shift - 1 : tyler window move-to-workspace 1
```

[Keybindings](docs/keybindings.md) has a full suggested set for all three tools.

## Configuration

Tyler reads `~/.config/tyler/tyler.toml`. After editing it, run `tyler config reload`. [`docs/tyler.toml`](docs/tyler.toml) is a sample with every
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
