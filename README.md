# tyler

Tiling windows for macOS, with workspaces that follow your fingers.

https://github.com/user-attachments/assets/d168cf84-ab63-4a10-8923-fb79e0c58f3d

tyler keeps each workspace as a list of windows and lays that list out for you, the way xmonad
does. Swap two windows or switch layouts and everything moves into place. Workspaces sit side by
side in a row. Swipe with three fingers and the windows move with you, then settle on the next
workspace when you let go. You don't have to turn off SIP.

> [!WARNING]
> tyler is alpha software. It has only been tried on macOS 26 on Apple silicon, it has
> [known issues](docs/known-issues.md), and commands and settings can change before 1.0.
> Run `tyler stop` before you turn off its Accessibility permission. Turning it off while `tylerd`
> runs can freeze the Mac until a forced restart.
>
> Almost all of tyler was written by [Claude Code](https://claude.com/claude-code). A human decides
> what to build, tries it on real windows and reviews the result. The code is unit tested and
> linted, but nobody has read every line. [`CLAUDE.md`](CLAUDE.md) and [`devdocs/`](devdocs) show
> how it's built.

## What you get

- Three [layouts](docs/layouts.md): `tall` (a main column with a stack beside it), `grid` and
  `full`. There's also `strip`, an experimental scrolling layout.
- Animated window moves, and a [three-finger swipe](docs/features.md#swiping-between-workspaces)
  between workspaces that tracks your fingers.
- [Mouse support](docs/features.md#resizing-with-the-mouse). Drag a window over another and the
  others make room. Drag the gap between two windows to resize them. Hold Option to move or resize
  a window from anywhere inside it.
- A row of workspaces for each display.
- Optional [focus follows mouse](docs/features.md#focus-follows-mouse).
- [Menu bar items](docs/features.md#menu-bar-items) that show your workspaces as numbers, or as a
  small map of every window:

  <img width="310" height="34" alt="tyler's menu bar items" src="https://github.com/user-attachments/assets/c031ff86-a4e3-4fa3-9488-6656dc0749dd" />

Everything is a `tyler` command, so anything that can run a command can drive it.

## How it compares

[AeroSpace](https://github.com/nikitabobko/AeroSpace) is the closest thing to tyler. It also fakes
workspaces without SIP changes, but it arranges windows in an i3-style tree instead of a list, and
it leaves out animations on purpose. It's much more mature than tyler and has hotkeys built in.
If you want something that's been tested by thousands of people, use AeroSpace.

[Amethyst](https://github.com/ianyh/Amethyst) has xmonad-style layouts too, but it works with
macOS Spaces. tyler has its own workspaces, so switching doesn't depend on Mission Control.

[yabai](https://github.com/koekeishiya/yabai) can do more than tyler, but some of its features
need SIP partly turned off.

tyler has a few limits worth knowing up front. It has no hotkeys of its own, and it doesn't start
at login yet. On a display with another display beside it, workspaces switch instantly instead of
sliding. Parked windows also leave a thin line at the edge of the screen, because macOS keeps every
window at least one point on screen.

## Requirements

- macOS 14 or later (only macOS 26 on Apple silicon has been tried so far)
- The Xcode Command Line Tools with Swift 6 (`xcode-select --install`), since Homebrew builds tyler
  from source
- Accessibility permission for `Tyler.app`, which tyler asks for on first start

tyler moves windows through the public Accessibility API and needs no scripting additions. It does
use private macOS calls in two small places: one reads a window's ID, and the other helps show the
resize cursor over a gap. If a macOS update removed that second one, you'd only lose the cursor.

## Installation

```bash
brew install dhansmair/tyler/tyler
tyler start
```

macOS will ask for Accessibility permission. Turn on `Tyler.app` in System Settings > Privacy &
Security > Accessibility, and tyler tiles your windows within a few seconds. If it doesn't, run
`tyler restart`.

`tylerd` keeps running in the background after you close the terminal. `tyler status` shows how
it's doing, and `tyler stop` puts every window back where it was.

For the swipe, set *Swipe between full-screen applications* to four fingers (or off) in System
Settings > Trackpad > More Gestures. Otherwise macOS reacts to the same swipe.

Other ways to install:

```bash
brew install dhansmair/tyler/tyler@v0.x.y  # a specific version
brew install --HEAD dhansmair/tyler/tyler  # the latest main
```

To build it yourself, see [Installing from source](docs/install-from-source.md).

### Updating

```bash
brew upgrade tyler
tyler restart
```

tyler isn't properly signed yet, so macOS treats each new build as a new app and asks for the
permission again. `tyler restart` handles this: it puts your windows back, clears the old entry in
System Settings, and returns the windows to their workspaces once you turn `Tyler.app` on.

### Starting at login

There's no login service yet. You can run `tyler start` from your shell instead, for example in
`~/.zprofile`:

```bash
tyler start >/dev/null 2>&1   # does nothing if tylerd already runs
```

### Uninstalling

```bash
tyler stop                                              # puts every window back
tccutil reset Accessibility io.github.dhansmair.tyler   # removes Tyler.app's permission
brew uninstall tyler
rm -r ~/Applications/Tyler.app
rm -r ~/.tyler ~/.config/tyler                          # the socket, log and config
```

Reset the permission before you delete the app, because `tccutil` can only find an app that's
still there.

## Keybindings

tyler leaves hotkeys to [skhd](https://github.com/koekeishiya/skhd),
[Karabiner-Elements](https://karabiner-elements.pqrs.org) or [Raycast](https://www.raycast.com).
With skhd, it looks like this:

```
alt - j : ~/.local/bin/tyler window focus next
alt - k : ~/.local/bin/tyler window focus prev
alt - return : ~/.local/bin/tyler window swap master
alt - 1 : ~/.local/bin/tyler workspace focus 1
alt + shift - 1 : ~/.local/bin/tyler window move-to-workspace 1
```

[Keybindings](docs/keybindings.md) has a full suggested set for all three tools.

## Configuration

tyler reads `~/.config/tyler/tyler.toml`. The file is optional, and every setting has a default.
Run `tyler config reload` after you edit it.

```toml
[gaps]
inner = 8
outer = 8

[mouse]
focus-follows = true

[apps.Firefox]
workspace = 2
```

[`docs/tyler.toml`](docs/tyler.toml) is a sample with every setting, and the
[manual](docs/manual.md#configuration) explains each one.

## Documentation

- [Manual](docs/manual.md): concepts, running tylerd, the config file, every command
- [Layouts](docs/layouts.md) and [Features](docs/features.md)
- [Keybindings](docs/keybindings.md) and [Troubleshooting](docs/troubleshooting.md)
- [Known issues](docs/known-issues.md) and the [changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md), and how tyler is built: [`CLAUDE.md`](CLAUDE.md),
  [`devdocs/design.md`](devdocs/design.md)

## License

[MIT](LICENSE)
