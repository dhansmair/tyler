# Troubleshooting

When something goes wrong, two commands put things right:

- `tyler tiling off` stops tyler from moving windows and brings every parked window back.
- `tyler stop` stops `tylerd` and puts every window it moved back where it was.

## Where to look

- `tyler status` says whether `tylerd` runs, which binary and config it uses, and whether tiling is
  on or waiting for permission.
- `tyler window list` shows every window `tylerd` knows, with its workspace, slot and frame.
- `tyler debug at` shows what `tylerd` sees and decides at the pointer, and `tyler debug windows`
  where its picture of the windows differs from macOS's (see the
  [manual](manual.md#debug-at)).
- `~/.tyler/tyler.log` holds what `tylerd` printed since `tyler start`, and its log at
  `log.level`: warnings and errors unless you change it. The run before, up to the last `tyler
  start` or `restart`, is in `~/.tyler/tyler.log.1`. For more while you look into
  something, run `tyler config set log.level info` (or `debug`), reproduce the problem, and read
  the end of the file: `tail -n 30 ~/.tyler/tyler.log`, or `grep pointer ~/.tyler/tyler.log`.
  Each line has the date and time, the level, a category (`ax`, `manager`, `pointer`, `ipc`,
  `indicator`, `tylerd`) and what happened, such as `window focusing - #7349 (Firefox)`: a window by its number and app, never its title. `tyler restart` or `config reload` puts the level back.
- `log stream --predicate 'subsystem == "tyler"'` shows the same lines and more in the unified log
  (it may need an administrator).

## Nothing is tiled, or commands say there is no permission

`tylerd` needs Accessibility permission, and macOS gives it to the app that started `tylerd`: the
terminal you ran `tyler start` in. Open System Settings > Privacy & Security > Accessibility and
turn that terminal on (add it with `+` if it isn't listed). `tylerd` notices within a second; no
restart needed. If you start `tylerd` from another terminal app later, that one needs the
permission too. When `tylerd` runs as an app (`tyler status` shows a `binary` inside
`Tyler.app`), the permission belongs to `Tyler.app` instead, whichever terminal you use; `tyler
start` makes macOS ask for it. If `tylerd` doesn't notice within a few seconds, run `tyler
restart`.

If the terminal is listed and on but nothing happens, macOS may have kept a stale entry (after an
app updates, or after restarting the Mac or logging in again). `tyler start` and `tyler status`
then say `Accessibility calls refused although the permission is on` or `sees none of the windows
on screen`. Run `tyler stop` first, then remove the terminal with `−`, add it again, and run
`tyler start`. For `Tyler.app`, remove it with `−` and run `tyler start`, which asks again.

If `tyler status` says `waiting for the screen to be unlocked`, nothing is wrong: macOS shows no
windows while the screen is locked, and `tylerd` starts once it is unlocked.

**Always stop `tylerd` before you switch off or remove its Accessibility permission** (its
terminal's, or `Tyler.app`'s).
macOS can stop all keyboard and mouse input when that permission is taken away from a process
watching the mouse buttons, as `tylerd` does. The pointer still moves, but nothing can be clicked
or typed, and only a forced restart (holding the power button) gets out of it.

## `tylerd is not running`

Run `tyler start`. If it exits right away, it prints the end of `~/.tyler/tyler.log`, which says
why. A broken config file doesn't stop it: `tylerd` logs the error and starts with the defaults.

## A window is gone

It is most likely parked: moved just past the edge of its display, with a one-point column showing.

- `tyler window list` shows its workspace; `tyler workspace focus <n>` brings it into view. Cmd-Tab
  to its app also switches there.
- If `tylerd` crashed or was killed with `kill -9`, windows of other workspaces stay parked. Run
  `tyler start`: it tiles every window it finds, parked ones included. A `tyler stop` afterwards
  leaves them in view.
- `tyler tiling off` brings every parked window back at once.

## A window isn't tiled

- Dialogs, sheets and panels are never tiled, nor are windows you floated with `tyler window float
  toggle` (`window list` shows them as `dialog`, `float`, `other` or `floated`).
- Windows of apps without a Dock icon (menu bar apps) aren't tracked.
- Windows in native fullscreen, and windows on another macOS Space, are left alone. tyler works
  best with one Space per display: its workspaces replace Spaces.
- A window that appeared while the app was busy may only be picked up once you focus it.

## A window doesn't fill its slot

Some apps have a minimum size (System Settings, for example), and terminals size their windows in
whole character cells. macOS then keeps the window a little larger or smaller than its slot.

## A swipe also switches Spaces or goes back a page

macOS's own swipes still work alongside tyler's. In System Settings > Trackpad > More Gestures, set
*Swipe between full-screen applications* to four fingers (or off), and make sure *Swipe between
pages* doesn't use three fingers. Or set `gestures.fingers = 4` and keep macOS on three. See
[Swiping between workspaces](features.md#swiping-between-workspaces).

## Swipes, focus follows mouse or Option-drag do nothing

`tyler status` lists what `tylerd` listens for on the `input` line. A feature missing from it is
off in the config; `(refused by macOS)` after it means macOS wouldn't let `tylerd` listen, usually
for want of the Accessibility permission. macOS also turns a listener off when `tylerd` is slow to
answer it, for instance just after waking from sleep. `tylerd` checks every 2 seconds and turns it
back on, and `tyler status` says how often that happened. If a feature still does nothing, run
`tyler restart`.

## Option-drag doesn't work in an app any more

While `mouse.modifier` is `"option"` (the default), Option-drag anywhere in a window moves it, so
Finder's Option-drag copy and block selection in terminals don't reach the app. Set
`mouse.modifier = "none"` (or another combination, such as `"ctrl+option"`) and run `tyler config reload`.
Option-click still reaches the app.

## `unknown request: tylerd is probably older than tyler`

You updated `tyler` but `tylerd` still runs the old version. Run `tyler restart`; windows stay where
they are.

## A workspace comes into view on its own

Focus moved to a window on that workspace: an app focused one of its windows (as some do when a
window closes or opens), or focus follows mouse moved the focus to an app. With `log.level` at
`info`, the log says which window: `workspace switching - 2 on display 1 - focus moved to #7349
(Firefox)`. At `debug` it also has a `window focused` line for each focus `tylerd` reads.

## Windows move on their own after plugging in a display

macOS moves windows when displays change, and tyler places every window again about a second after
macOS is done. If something still looks wrong, `tyler workspace retile` puts the current workspace's
windows back into their slots.

## The map or the workspace numbers are missing from the menu bar

On a Mac with a notch, macOS hides menu bar items that don't fit beside it, without saying so.
tyler's items are among them when the menu bar is full: turn off an item you don't need
(`indicators.text.enabled` or `indicators.map.enabled`, or another app's), or hold Command and
drag tyler's item further right.

## Slides, swipes or resizes are jerky

At `log.level` `info`, every slide, swipe and drag that moved windows leaves one line on what it
cost:

```
slide finished - 23 frames (longest gap 56.0 ms), 46 writes in 93.6 ms, slowest 47.1 ms #3993 (Microsoft Edge), 45 updates
```

A slide has at most 31 frames, 8 ms apart. Fewer frames and long gaps mean the windows' apps were
slow to move them, and the slowest write names the window that held it up most. Include these
lines when you report it.

## Reporting a bug

See [CONTRIBUTING.md](../CONTRIBUTING.md#reporting-a-bug) for what to include. The
[known issues](known-issues.md) may already describe it.
