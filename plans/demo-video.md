# Demo video for the README

A video of about a minute at the top of the README that shows what tyler is in practice. It
replaces the alpha item "a GIF or screenshot of a slide and the map" (`plans/alpha-release.md`).

It is recorded in two parts in one take, with OBS recording the screen throughout:

1. **Scripted** (`devtools/demo-video`): opening windows, focusing, swapping, the layouts, a
   second workspace and switching between the two. The script presses real hotkeys, so the
   keystroke overlay shows the keys a user would press.
2. **By hand**: what a script can't do convincingly, the trackpad and the mouse.

## Decisions

| # | Question | Decision |
|---|----------|----------|
| V1 | How viewers see what triggered a move | **Real hotkeys and a keystroke overlay** (KeyCastr). The script posts the key presses, a hotkey daemon runs the `tyler` command, KeyCastr shows the keys. The keys are the suggested set of `docs/keybindings.md`, so the video matches the docs. |
| V2 | Where it is recorded | **In a normal account, on spare workspaces.** The script checks that the two workspaces it uses are empty and touches nothing else. Keeping personal things out of the picture is a checklist (below), not something the script can guarantee. |
| V3 | Layouts shown | `tall`, `grid` and `full` (the default cycle). Not the strip: it is experimental. |
| V4 | Format in the README | **MP4 uploaded to GitHub** (a `user-attachments` URL, which the README renders as an inline player), not a GIF: a minute of slides as a GIF is tens of MB and drops frames. A video committed to the repository doesn't play inline. Free accounts may upload videos up to 10 MB. |

## Storyboard

`A` and `B` are the two spare workspaces (for example 5 and 6, after raising `workspaces.count`
for the recording). Pauses are a setting of the script, so the pace can be tuned after a dry run.

| # | What happens | Keys |
|---|--------------|------|
| 1 | Workspace `A`, empty: the wallpaper and the menu bar item, about 2 s | |
| 2 | Safari opens and fills the screen; TextEdit opens beside it; Preview opens (one left, two right); Terminal opens (three stacked on the right) | |
| 3 | Focus moves round the list | Option+J ×3, Option+K |
| 4 | Swaps: the focused window moves down the list, then to the master | Option+Shift+J ×2, Option+Return |
| 5 | The master column widens and narrows | Option+L ×3, Option+H ×3 |
| 6 | Layouts: grid (the four corners), then full; in full, focus brings each window to the front; back to tall | Option+Space, Option+Space, Option+J ×2, Option+Space |
| 7 | Terminal is sent to workspace `B`: it slides away to the right, and the other three re-tile | Option+Shift+`B` |
| 8 | To workspace `B`: the windows slide out to the left, Terminal is there alone | Option+`B` |
| 9 | A second terminal opens beside it; swap them | Option+Shift+J |
| 10 | Back and forth between `A` and `B` twice, slowly enough to see the slide | Option+`A`, Option+`B`, … |
| 11 | The script plays a short sound and stops: the hand-over | |

Then by hand, roughly in this order:

| # | What happens |
|---|--------------|
| 12 | Trackpad swipe between `A` and `B`: a slow one that follows the fingers, one let go halfway that springs back, then a flick |
| 13 | On `A` in tall: drag the gap between the columns (the master ratio follows), then the gap between two stacked windows |
| 14 | Drag one window by its title bar onto another: the preview, then the swap on release |
| 15 | Option-drag inside a window to move it onto another (swap), Option-right-drag to resize it (`mouse.modifier`) |
| 16 | Click a workspace in the menu bar map to switch |
| 17 | Optional: Cmd-Tab to an app on the other workspace (it slides there), Option+T to float a window |

Where the mouse is the point, make it visible: a larger pointer (System Settings >
Accessibility > Display > Pointer size), OBS capturing the cursor, and KeyCastr's mouse click
display. Check in the dry run that KeyCastr shows Option while it is held during a drag; if not,
that step needs a caption in editing.

## The script: `devtools/demo-video`

A bash script beside `devtools/live-check`, run from a terminal on another workspace (its own
window is then parked and out of the picture).

- **One table of actions** (name, key, `tyler` command) drives both halves: from it the script
  writes a temporary skhd config, and the storyboard presses keys by action name. So the keys
  pressed and the keys bound can't drift apart. The `tyler` in the config is the one next to the
  script's `tyler` (`command -v tyler`).
- **Key presses** are posted with `CGEvent` at the HID tap by a `key` subcommand of
  `devtools/live-check` (it already posts clicks for `mod-drag`), so both skhd's and KeyCastr's
  event taps see them. Fallback if they don't: System Events via `osascript`.
- **Hotkeys:** with `--skhd` the script stops the skhd service, runs skhd with the demo config
  for the length of the run and starts the service again at the end (also on Ctrl-C, through a
  `trap`). Without it, the user binds the suggested set themselves.
- **Opening windows:** `open -a` with a file or URL per app; Terminal windows through
  `osascript` (`do script`), each running a harmless command (`top`, `less` on the README). The
  script waits until `tyler window list --json` shows the new window tiled before going on, and
  remembers each window's ID.
- **Content:** Safari on a public page given by `--url` (its start page shows favourites and
  history), TextEdit on a copy of `docs/tyler.toml`, Preview on one of the wallpapers macOS
  ships in `/System/Library/Desktop Pictures`. Apps and commands are variables at the top.
- **Preflight**, before anything moves: tylerd runs and tiling is on; workspaces `A` and `B`
  exist and are empty; none of the demo apps has a window on another workspace (activating the
  app could bring that window forward and switch workspaces); `layouts.cycle` is tall, grid,
  full; the terminal may post events. Then it switches to `A` with a plain `tyler` command and
  waits for Enter, so recording can start on the empty workspace.
- **Cleanup** (asked, at the end): quit the demo apps that weren't running before, restore skhd.
  Nothing is closed by "the focused window": only the apps the script itself started.

## Before recording (checklist)

- [ ] Raise `workspaces.count` for the session if fewer than two workspaces are empty
  (`tyler config set workspaces.count 6`; `config reload` undoes it).
- [ ] Hide desktop icons, pick a neutral wallpaper, hide menu bar items that show personal things
  (or crop the menu bar to tyler's item and the clock in editing).
- [ ] Do Not Disturb on, so no notification shows up.
- [ ] Terminal's window title without user and host name (Settings > Profiles > Window), or a
  profile for the demo.
- [ ] A US keyboard layout as input source if KeyCastr shows Option+letter as the special
  character it types on the current one.
- [ ] KeyCastr: position (bottom centre), size, fade time; mouse clicks on.
- [ ] OBS: macOS Screen Capture of the one display, 60 fps (slides look jerky at 30), cursor on,
  no audio, the canvas at the display's resolution.
- [ ] A dry run without recording, to tune the pauses.

## After recording

- [ ] Trim, cut the waits, speed up nothing that moves (a sped-up slide misrepresents it).
- [ ] Encode: `ffmpeg -i raw.mov -vf "fps=60,scale=1600:-2" -c:v libx264 -crf 26 -preset slow -pix_fmt yuv420p -an -movflags +faststart demo.mp4`;
  raise `-crf` or lower the scale until it is under 10 MB.
- [ ] Watch it for anything personal: window titles, the menu bar, the Dock, notifications.
- [ ] Upload it by dragging it into the README in GitHub's web editor (or an issue comment) and
  put the `https://github.com/user-attachments/assets/…` line under the README's title. Check
  that it plays while logged out once the repository is public.

## Increments

1. `live-check key <combination>...`. Done (2026-10-15): skhd's tap sees the keys posted at the
   HID tap (Option+J, Option+K moved the focus and back). Still to check: KeyCastr shows them.
2. `devtools/demo-video` with the action table, the skhd config, preflight and the storyboard;
   a dry run on real windows.
3. Recording and the README (by hand), then tick the alpha item and delete this plan.

## Open questions

- Whether KeyCastr shows keys posted at the HID tap, held modifiers included.
