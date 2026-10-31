# Features

What tyler does beyond the commands: the trackpad, the mouse, the menu bar and several displays.
The terms (display, workspace, tiling list, slot) are explained in the
[manual's Concepts](manual.md#concepts), the settings in its
[Configuration](manual.md#configuration) section.

- [Swiping between workspaces](#swiping-between-workspaces)
- [Resizing with the mouse](#resizing-with-the-mouse)
- [Moving windows by dragging](#moving-windows-by-dragging)
- [Moving and resizing with the modifier](#moving-and-resizing-with-the-modifier)
- [Focus follows mouse](#focus-follows-mouse)
- [Menu bar items](#menu-bar-items)
- [Several displays](#several-displays)
- [App assignments](#app-assignments)
- [Performance](#performance)

## Swiping between workspaces

Swipe sideways with three fingers on the trackpad to move between workspaces. The windows follow your fingers. Swipe left to bring in the next workspace from the right, and swipe right to bring in the previous one; from the first workspace, a swipe right wraps around to the last. When you lift your fingers, the next workspace comes into view if you swiped more than halfway, or with a quick flick even before that; otherwise the windows slide back. Changing your mind halfway works too: swipe back past where you started and the other neighbour comes in instead. The workspace that comes into view gets the focus, as with `tyler workspace focus`. With several displays, the swipe moves the workspaces of the display under the pointer.

On a workspace in the experimental `strip` layout, the swipe scrolls the strip instead and never switches workspaces (see [Layouts](layouts.md#strip--experimental)). If the focused window scrolled out of view, the nearest window in view gets the focus. Use `tyler workspace focus` to leave a strip workspace.

A swipe does nothing while tiling is off, while you drag a window, or when there is only one workspace. Vertical swipes and swipes with another number of fingers are left to macOS. Any command in the middle of a swipe puts the windows back first.

macOS has its own sideways swipes, and tylerd doesn't stop them: in System Settings > Trackpad > More Gestures, set *Swipe between full-screen applications* to four fingers (or off), and make sure *Swipe between pages* doesn't use three fingers. Otherwise a swipe may switch Spaces or go back a page as well. To use four fingers for tyler instead, set `gestures.fingers = 4` and give macOS's swipe three fingers or turn it off. `gestures.swipe = false` turns swiping off, and `gestures.swipe-distance` sets how far your fingers travel for a whole workspace.

## Resizing with the mouse

In `tall`, drag the edge between two tiled windows and the layout follows while you drag (in steps at most `mouse.follow-interval` apart):

- the edge between the master and the stack sets the master ratio (the same one `tyler layout ratio` changes)
- the edge between two stacked windows sets their heights; the other stacked windows keep theirs

In `grid`, the edge between two columns sets their widths and the edge between two windows of a column their heights; the other columns and rows keep theirs.

With `gaps.inner` set, you can also drag the gap between two windows instead of an edge: it moves the divider the same way, both windows follow, and the focus stays where it was. While the pointer is over a gap you can drag, it turns into the resize arrows. A click in a gap, without moving the mouse, does nothing. Where two gaps cross there is nothing to grab, and a window in front of the gap (a floated one, or another app's) gets the press. Set `mouse.gap-resize = false` to turn this off.

When you let go of the mouse button, every window snaps into its slot. Edges that aren't between two windows (the outer edges, the master's top and bottom) snap back, and so does a window you moved by its title bar without dropping it on another one (see below). A divider stops before either neighbour drops below a tenth of their shared space. Sizes belong to the slot, not the window: a window that moves into a slot takes its size. Each workspace keeps its own sizes, `tall`'s and `grid`'s apart, and `tyler restart` keeps them. `full` doesn't follow the mouse; windows snap back.

Each step of following a drag moves every other window, and slow apps take a while to move. A shorter `mouse.follow-interval` looks smoother but can fall behind the mouse with slow apps; a longer one keeps up but moves in coarser steps. `0` follows every resize the app reports.

## Moving windows by dragging

Drag a tiled window by its title bar over another tiled window's slot, and the windows make room for it there, to show what will happen (`animations.drag-preview` sets how long they take; 0 moves them at once): the dragged window takes that place in the tiling list, and the windows between its old place and the new one each move one place along, into the slot next to theirs. With three windows in `tall`, dragging the lower right one over the master's slot shows the master moving to the upper right and the upper right one moving down. Let go there, and the windows stay that way, each with the size of its new slot. Move on to another slot and the windows make room there instead; move back over the dragged window's own slot or outside the tiled area, and they go back. Over a gap, what the preview shows stays.

What counts is the slot under the mouse pointer, not the one the dragged window covers most. Letting go outside the tiled area or over the window's own slot puts it back in its slot. The window you drag keeps focus. In `full` every window fills the same area, so dragging never moves one there. Floated windows take no part: you can't drag one into the layout, and a tiled window never makes room for one. A command or a workspace switch in the middle of a drag ends it, and the windows go back to their slots.

In `tall`, the master section and the stack each make room within themselves: drag a window from the stack onto the left column and it joins the master section at the slot under the pointer, and the other way round. Use `tyler window promote` and `demote` to do the same from the keyboard.

Dragging a window onto another display moves it to the workspace on screen there when you let go, and that display then has the focus. While you drag, there is always exactly one open slot: the one the window will take. Over the other display, its windows make room where the window would go, and the windows of its own display close up as if it had left. The open slot is the one under the pointer: in `tall`, over the left column the window joins the master section there, above or below the windows in it, and over the upper or lower part of the right column it goes into the stack there. Over a gap the open slot stays where it was. Drag it back over its own display and both displays go back to how they were; letting go there puts it back (or moves it, as above).

## Moving and resizing with the modifier

Hold the modifier (Option unless `mouse.modifier` says otherwise) and drag anywhere in a window, not only its title bar or edges:

- **with the left button to move it.** A tiled window follows the pointer and goes in at the slot you drop it on, or moves to the display you drop it on, as when you drag it by its title bar (see [Moving windows by dragging](#moving-windows-by-dragging)). Dropped anywhere else, it goes back to its slot. A floated window moves where you take it.
- **with the right button to resize it.** The quarter of the window you grab decides which edges move: grab it near the bottom right corner and the bottom and right edges follow the pointer. A tiled window resizes as when you drag its edges (see [Resizing with the mouse](#resizing-with-the-mouse)), and only its edges between two windows can move: if you grab the half beside the display's border, the edge on the other side moves instead, so the lower window on the right grows upward and leftward wherever you grab it. A floated window resizes freely, down to 50 points a side.

The window you grab gets the focus. A click with the modifier, without moving the mouse, still goes to the app: Option+click in an editor, Option+right-click for a menu with extra items. A drag with the modifier never does: while `mouse.modifier` is set, Option-drag in apps (copying a file in Finder, a block selection in a terminal) is tyler's. Set it to `"none"` to turn this off, or to another combination such as `"ctrl+option"`.

Nothing is grabbed, and the press goes to the app, outside the area windows tile in (the menu bar, the Dock), over a menu, the desktop or a window tyler doesn't tile or float, during a slide, a swipe or another drag, and while tiling is off. If tylerd is busy for about a second when you press (an app slow to answer), macOS gives that press to the app instead.

## Focus follows mouse

With `mouse.focus-follows = true`, moving the pointer onto a window and letting it rest there for a moment (`mouse.focus-delay`, 100 milliseconds by default) focuses that window and brings it to the front, as clicking it would. Sweeping the pointer across windows on the way somewhere else focuses none of them. It works on every display: resting on a window of another display focuses that display too. It is off by default.

A rest on an empty workspace on another display focuses it, as switching to it would: commands and new windows go there, and what you type no longer reaches the window you left. A rest over the wallpaper of a workspace with windows changes nothing.

Only moving the pointer moves the focus. Windows that slide or re-tile under a pointer that stays still change nothing, so focus you set from the keyboard (`tyler window focus`, `tyler workspace focus`) stays where it is until you move the mouse. Nothing is focused:

- over a parked window's one-point column at the edge of the display, or a `strip` window out of view, so the pointer never switches workspaces. A `strip` window partly in view is focused like any other, which scrolls the strip to show it whole
- outside the area windows tile in (the menu bar, the Dock), over a menu, the desktop or a window tyler doesn't tile or float
- while a menu is open anywhere, so moving off it doesn't close it
- while a mouse button is held (you're resizing or dragging), during a slide or a swipe, and while tiling is off

A floated window in front of a tiled one gets the focus while the pointer is on it; moving on to the tiled window around it brings that one to the front.

## Menu bar items

While `tylerd` runs, it shows the workspaces in the menu bar twice: as text and as a map. `indicators.text.enabled` and `indicators.map.enabled` turn either off. With several displays, they show the focused display's workspaces.

The text item reads, for example, `1 [2] 3 4  ▥`:

- the number of each workspace, from left to right: the one on screen is in brackets (`[2]`), and empty ones are faint
- the symbol of the current workspace's [layout](layouts.md): `▥` for tall, `▦` for grid, `▢` for full, `↔` for strip

Without tiling it says `tyler: tiling off`, and before Accessibility permission is granted `tyler: no access`. Clicking it opens a menu to switch workspaces, cycle the layout and turn tiling on or off; these do the same as the `tyler` commands. At its bottom, Reload config does what `tyler config reload` does, Open config opens the config file (creating an empty one if there is none) with `editor.command` if you set it, else in `$VISUAL` or `$EDITOR` in Terminal, else in your default text editor (as `tyler config edit` does outside a terminal), and Quit tyler stops `tylerd` like `tyler stop`, putting the windows back where they were.

The map, left of the text, has a small thumbnail for each workspace, from left to right, with a rectangle for each tiled window where its layout puts it (in full, the windows share one rectangle; in strip, only the windows in view show, cut at the thumbnail's edge). The workspace on screen is the bright one (the windows of the others are dimmed), each window shows its app's icon when there is room for it (`indicators.map.show-icons = false` turns them off), and the focused window is filled light blue (your accent colour, lightened, if you changed it in System Settings). Click a thumbnail to switch to that workspace; right-click or ctrl-click the map to open the same menu as the text item. The map is hidden while tiling is off.

App icons are detailed for a box this small. `icon` in an app's table, `[apps.<app>]`, gives it a simpler icon instead, either:

- the name of an [SF Symbol](https://developer.apple.com/sf-symbols/), such as `globe`, `terminal` or `doc.text` (the free SF Symbols app lists them all), or
- one glyph of a [Nerd Font](https://www.nerdfonts.com), which has simple logos of many apps, such as Firefox's. Write it by its code point from the [cheat sheet](https://www.nerdfonts.com/cheat-sheet): `""`, `"\U000F0239"`, or the surrogate pair the cheat sheet shows for code points past `FFFF`, `"󰈹"`. The glyph is drawn in `indicators.map.icon-font`, by default Symbols Nerd Font (`brew install --cask font-symbols-only-nerd-font`); any installed Nerd Font works.

Name the app as in [App assignments](#app-assignments). The icon is cut out of the window's box, so it reads in light and dark menu bars. Apps without an icon, symbol names macOS doesn't know, a font that isn't installed and glyphs the font doesn't have all show the app's icon (tylerd logs which, under `log stream --predicate 'subsystem == "tyler"'`).

On a MacBook with a notch, macOS hides menu bar items that don't fit next to it.

## Several displays

Every display is tiled, with its own row of workspaces. Workspace numbers are shared by all displays: with the default of four workspaces each, the main display (the one with the menu bar) has 1 to 4 and a second display 5 to 8. `workspaces` in a display's table of the config file, `[displays.<n>]`, chooses them instead.

- **The focused display.** Commands act on the focused display: the display of the focused window, or the one a command or a rest of the pointer last went to (so an empty workspace keeps its display). `tyler workspace focus 5` switches on whichever display holds workspace 5 and focuses that display; `prev` and `next` stay on the focused display. Focusing a window (a click, Cmd-Tab) focuses its display, and a parked window's workspace comes into view on its own display. When you close a window or quit an app and macOS picks a parked window to focus next, the workspace stays where it is and the focus goes to a window on it. The menu bar shows the focused display's workspaces. A swipe acts on the display under the pointer and focuses it.
- **Moving between displays.** `tyler display focus` focuses another display, `tyler window move-to-display` sends a window to one, and `tyler workspace move-to-display` moves a whole workspace to one. `tyler window move-to-workspace 6` can send a window to another display's workspace: it parks there, or takes its slot if that workspace is on screen. A window you drag onto another display takes the slot under the pointer (see [Moving windows by dragging](#moving-windows-by-dragging)); a window you move to another display any other way (the Window menu, another tool) goes last in that display's workspace on screen.
- **Displays side by side.** Parked windows wait at an edge of their display that touches no other display: the right edge, or the left one if another display lies to the right. On a display with another display beside it, switching workspaces is instant rather than a slide, so no window passes over the other display.
- **Displays that come and go.** When a display is unplugged, its workspaces wait on the main display's row; when it comes back, they go back to it. tylerd waits about a second after macOS reports a change, then places every window again.

**New windows.** A new window opens on the workspace you are on, even if macOS or the app first puts it on another display, where it may show for a moment. This includes windows an app restores when it launches. A window that opens while a mouse button is down, such as a tab torn off a browser, stays where you dropped it, and so do windows opened while tiling is off and windows that were open when `tylerd` started. An app's `workspace` setting wins.

## App assignments

`workspace` in an app's table of the config file sends its new windows to a workspace, for example `workspace = 3` under `[apps.Firefox]`. An assignment applies once, when a window is tiled for the first time: when it opens, or when `tylerd` starts and finds it open. If the workspace isn't on screen, the window is parked there. Apps usually focus a window they open, and focusing a parked window switches to its workspace, so you follow the window there; a window that opens in the background just waits on its workspace. After that, the window behaves like any other: `window move-to-workspace` moves it, and it stays where you put it. See [Configuration](manual.md#configuration) for how to name apps.

## Performance

tylerd moves windows the only way macOS allows without SIP changes: by asking each app, through
the Accessibility API, to move its window. Every move is a round trip to the app, which takes
1–3 ms, and longer while the app redraws (a terminal reflowing its text takes about 10 ms). What
tylerd itself computes (layouts, slides, swipes) takes microseconds, so all the work goes into
asking the apps as little and as cleverly as possible:

- **Slides move windows, not sizes.** Each step of a slide or swipe is a single move per window;
  windows are resized only at the end.
- **The steps keep time.** A slide lasts 250 ms whatever happens: a slow app makes it coarser,
  never longer. A swipe takes a step every 8 ms, or as fast as the apps answer when that is slower,
  and moves in between are dropped, so the windows always show where your fingers are.
- **Resizing asks for less.** While you drag an edge or a gap, the other windows get two writes
  each (a move and a resize, in the order that keeps them clear of the display's edge) and are
  not read back; when you let go, every window is placed exactly. The layout follows at most every
  `mouse.follow-interval` (16 ms), with that interval kept free after each step, so the apps'
  replies never pile up behind the mouse.
- **Dragging with the modifier** follows the pointer at the same pace: the newest position wins.
- **The apps move their windows side by side.** The steps of a slide, swipe or modifier drag go
  to a queue per app and tylerd doesn't wait for them: a slow app skips frames instead of holding
  up the other windows, and tylerd stays free to follow your input. A window's final placement
  waits for its app's queue, so it always lands last.
- **Echoes are cheap.** Every move comes back from the app as a notification. tylerd reads only
  the frame for a move, and reads each window once per burst of notifications.

Measured on real windows (terminals, an editor and browsers, on one display, macOS 26.7):

| | Before this work | Now |
|---|---|---|
| Frames per 250 ms slide | 19–29 of 31 | 30–31 of 31, about 10 ms apart |
| tylerd busy moving windows during a slide | 50–140 ms | about 1.5 ms |
| A slide with a frozen app on screen | up to 1 s per frame | 31 smooth frames; that app's are skipped |
| Time between swipe steps | the writes + 8 ms (17–35 ms) | 8 ms, or the writes when slower |
| A neighbour's write during a resize | about 20 ms | about 8–10 ms |
| Steps while resizing | every 50 ms plus the writes | every 16 ms plus the writes |
| Updates read per move | about 2.2 | about 1.8 |

A frozen app still delays the end of a switch once: its window's final placement waits out the
Accessibility timeout (1 s). For the next 5 seconds its windows are left where they are and aren't
focused, so later switches and commands don't wait for it again.

To see the numbers on your own machine, set `tyler config set log.level info`: each slide, swipe
and drag leaves a line in `~/.tyler/tyler.log` with its frames, the time spent moving windows and
the slowest app (see [Troubleshooting](troubleshooting.md#slides-swipes-or-resizes-are-jerky)).
