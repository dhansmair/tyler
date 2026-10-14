# Layouts

A layout turns a workspace's [tiling list](manual.md#tiling-list) into window frames, within the
display's visible area (the screen without the menu bar and the Dock). Each workspace has its own
layout: `tyler layout set` sets it by name, and `tyler layout next` goes to the next layout of
`layouts.cycle` in the [config file](manual.md#configuration) (by default `tall`, then `full`: the
experimental `strip` is left out unless you add it). From a layout the cycle doesn't list,
`layout next` goes to the cycle's first. The menu bar shows the current layout's symbol, and its
menu follows the cycle too. A new workspace starts in `layouts.default` (`tall` unless you change
it); workspaces that already exist keep their layout across `tyler config reload` and `tyler restart`.

## tall (`▥`)

The master (the first window in the list) fills the left column, and the other windows are stacked
in the right column. One window fills the area; two sit side by side; three give one on the left
and two on the right.

The *master ratio* is the master column's share of the width, 0.5 to start with and between 0.1 and
0.9. Each workspace has its own: `tyler layout ratio +0.05` widens the master column, and dragging
the edge between the columns with the mouse sets it too. Dragging the edge between two stacked
windows sets their heights; see [Resizing with the mouse](features.md#resizing-with-the-mouse).

## grid (`▦`)

Columns of windows, two high. Up to three windows the grid looks like `tall`; four take the
corners, and more windows add columns, up to four. After that each column holds three windows, then
four, and so on. The list fills the columns from the left, each from the top. When the windows
don't fill every column, the first column holds fewer, so with an odd number of windows the master
has the first column to itself:

| Windows | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Windows per column | 1 | 1, 1 | 1, 2 | 2, 2 | 1, 2, 2 | 2, 2, 2 | 1, 2, 2, 2 | 2, 2, 2, 2 | 3, 3, 3 |

The columns start equally wide and the windows in a column equally high. Dragging the edge between
two columns, or between two windows of a column, with the mouse sets their sizes; see [Resizing
with the mouse](features.md#resizing-with-the-mouse). The grid keeps these sizes apart from
`tall`'s, so switching between the two doesn't carry a drag over. The grid has no master ratio:
`tyler layout ratio` says so and changes nothing.

The grid isn't in the default `layouts.cycle`, since up to three windows it looks like `tall`. Add
it to use it with `layout next`: `cycle = ["tall", "grid", "full"]`.

## full (`▢`)

Every window fills the whole area, stacked one behind the other; the focused one is in front. `tyler
window focus next` brings the next one forward. Dragging a window's edges doesn't change the layout
(the window snaps back), and dragging one window onto another never swaps, since they all share one
place.

## strip (`↔`, experimental)

> **Experimental.** The strip works and is used daily, but its design isn't settled (the `quarter`
> size in particular), some cases aren't handled, and it may change in any release.

The windows form one long row of columns without gaps that scrolls left and right, as in niri or
PaperWM. The display shows a view of the row, so a column can be partly in view: a `full` window
after a `half` one shows its first half at the right edge. Windows wholly out of view wait parked at
the edge of the display, like the windows of other workspaces. At an edge with another display beside
it, a partly visible window is parked too, so it never reaches onto that display.

- **Sizes.** Each window has a size, set with `tyler window size`: `half` (half the width, the full
  height: the default, so two windows look like `tall`), `full` (the whole area), or `quarter` (two
  windows stacked in one half-width column). Other layouts ignore the size but keep it.
- **Scrolling.** Focusing a window out of view (`tyler window focus`, a click, Cmd-Tab) scrolls just
  far enough to show its whole column. `tyler window swap` and `tyler window size` scroll too, when
  they need to.
- **Swiping.** On a strip workspace a sideways swipe scrolls the strip, and never switches
  workspaces: use `tyler workspace focus` to leave it. When you lift your fingers, the strip settles
  on the nearest whole column; a flick goes on to the next one.

Not handled yet:

- `quarter` pairs follow from the list order, so `window swap`, or a new window opening between the
  two, splits a pair (each half then shows like `half`).
- Resizing with the mouse: dragging an edge snaps back. Swapping by dragging only works between
  windows in view.
- No rubber band at the ends of the strip: the content just stops.
- On a display with another display beside it, windows scrolling out may pass over the other
  display, and windows coming in from the right side may first jump from the left edge.

## Gaps

*Gaps* are the space between neighbouring windows (`gaps.inner`) and between the windows and the
edge of the area (`gaps.outer`), in points. They are the same in every layout and on every
workspace, and come from the [config file](manual.md#configuration).
