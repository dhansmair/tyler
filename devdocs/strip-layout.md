# Strip layout: current state

> **Experimental.** The strip layout is built, unit tested and merged into `main`, and has been
> tried on real windows. Its design isn't settled yet (quarters in particular), several edge
> cases aren't handled, and some behaviour hasn't been checked against real windows. Expect it to
> change. The other layouts don't depend on it.

This file describes the strip as it is now, with its known issues and open questions; its checks
against real windows are in `testing.md`. Keep this file current when the strip changes.

## What it is

A niri-like layout. A workspace's windows form one long row of columns, left to right in list
order, and the display shows a view of that row: as many whole columns as fit. Focusing a window
out of view scrolls the row, and so does a 3-finger swipe. It's `LayoutKind.strip`, shown as `↔`
in the menu bar, and `tyler layout next` cycles tall → full → strip.

## Behaviour

### Sizes and columns

Each window has a size (`WindowSize`), set with `tyler window size half|full|quarter|next`:

| Size | Column width | Height |
|---|---|---|
| `half` (default) | half the view | full |
| `full` | the whole view | full |
| `quarter` | half the view | half: two quarters next to each other in the list share a column |

- New windows are `half`, so two windows look exactly like `tall` at 50% (the frames are equal to
  the point, gaps included).
- Columns are **packed from the list**, not stored: `full` and `half` each make a column, and two
  consecutive `quarter`s make one, the first on top. A lone `quarter` fills its column like
  `half`.
- `window size quarter` **pairs**: it makes the next window `quarter` too, or the previous one if
  the next already shares a column or there is none. With neither free it is an error.
- Leaving a pair puts the mate back to `half`. That happens on another size, closing, floating,
  minimizing, or moving the window to another workspace (it arrives there as `half`).
- Sizes are kept in every layout (`tall` and `full` ignore them) and survive `tyler restart`. A
  window forgets its size when it leaves tiling.

### The view

- The view is stored as the first window of its leftmost column (`Workspace.firstVisible`), not
  in points, so it survives gap, display and Dock changes. The workspace owns it and asks the
  layout through `ScrollingLayout` (`restingViews`, `fittedView`, `scrollTarget`); only the strip
  scrolls. Other layouts leave the view alone, and switching to the strip fits it to the focused
  window.
- After every change (focus, insert, remove, swap, size), the view moves the least distance that
  shows the focused window's column whole. It never shows empty space past the strip's end when
  one more column on the left would fit.
- The columns follow each other without gaps, and the view always starts at a column boundary.
  If the next column doesn't fit (a full column after a half one), the view shows the part of it
  that fits, hanging off the display's edge.
- The view survives `tyler restart`.

### Windows out of view

- Windows out of view **park at the right edge** of the display, like the windows of other
  workspaces, because macOS won't take a window further off screen. A window counts as in view
  when any of its frame is on the visible area (`DisplayInfo.shows`), unless it reaches past an
  edge with a neighbouring display: it would reach onto that display, where macOS may cut it to
  that display's height, so it parks instead.
- A column wholly out of view lies wholly off the area, also with an outer gap wider than the inner
  one (`StripGeometry.left(ofColumnAt:halves:)`).
- They stay on their workspace even when the parked frame lies mostly on a display to the right.
- They don't move when you switch workspaces (only windows in view slide), and `tyler tiling off`
  brings them back to where they were before tylerd moved them.

### Scrolling

- `window focus`, `window swap`, `window size`, and a click or cmd-tab on a window out of view
  **slide** the strip to the new view (`ScrollPlan`).
- Windows coming in from the right start where they are parked. Windows leaving on the left stop
  at the edge (1 point visible, or a 56-point strip beside a left Dock), then park.
- Windows out of view at both ends of a scroll stay parked.
- The focus event a scroll causes doesn't interrupt it.

### Swiping

- On a strip workspace, the 3-finger swipe **scrolls the strip and never switches workspaces**,
  even when every window fits. Leaving a strip workspace takes
  `tyler workspace focus`.
- When the swipe begins, the views it can rest at are worked out (`ViewScroll`). The windows follow
  the fingers along the scroll between the two views the position lies between.
- On release, `Snap` picks a view: the nearest one, or the next one for a flick. If the focused
  window left the view, the nearest window in view gets focus.
- A swipe that hasn't left its first view moves nothing. At the strip's ends the content just
  stops.
- A command in the middle of a swipe puts the windows back where they were.

## Code map

| Piece | Where |
|---|---|
| `WindowSize`, `StripLayoutState` (sizes, pairing with `setSizeWithPartner`, `Codable`) | `Sources/TylerCore/Layouts/Strip/StripLayoutState.swift` |
| `StripLayout` (a `ScrollingLayout`) | `Sources/TylerCore/Layouts/Strip/StripLayout.swift` |
| `StripColumns` (packing, fit, end clamp, snap points), `StripGeometry` | `Sources/TylerCore/Layouts/Strip/StripColumns.swift` |
| `ScrollingLayout`, `LayoutStates.strip`, `LayoutKind.strip` | `Sources/TylerCore/Layouts/Layout.swift` |
| `Workspace.update(_:_:)` (changing a layout's state, then refitting), `adopt` (a window keeping its size on another workspace) | `Sources/TylerCore/Workspaces/Workspace.swift` |
| The view of any scrolling layout (`scrolls`, `refitView`, `scroll(toFirstVisible:)`, `views`) | `Sources/TylerCore/Workspaces/Workspace+View.swift` |
| `arrangement`, `placements` (in view only), `offView` | `Sources/TylerCore/Workspaces/Workspace.swift` |
| `restingPlacements` (parking what is out of view) | `Sources/TylerCore/Placement/Workspace+Parking.swift` |
| `ScrollPlan` (one scroll between two arrangements), `ViewSnapshot` (the view before a change) | `Sources/TylerCore/Motion/ScrollPlan.swift`, `ViewSnapshot.swift` |
| `ViewScroll` (a swipe: views, positions, segments) | `Sources/TylerCore/Motion/ViewScroll.swift` |
| `DisplayInfo.shows(_:)` (the in-view rule) | `Sources/TylerCore/Displays/DisplayInfo.swift` |
| The view in the state file | `Sources/TylerCore/Lifecycle/SavedState.swift` |
| `tyler window size` | `Sources/TylerServer/Layouts/LayoutController.swift` |
| `SwipeTarget.view`, where a swipe along the view puts the windows and where it settles (`SwipeSession`) | `Sources/TylerCore/Swipe/SwipeSession.swift` |
| How a swipe begins and settles; the swipe in progress and its pacing | `Sources/TylerServer/Swipe/SwipeController.swift`, `Swipe.swift`, `WindowManager+Swipe.swift` |
| Scrolling when a command or a focus change moves the view | `Sources/TylerServer/Tiling/TilingController.swift`, `Workspaces/WorkspaceController.swift` |
| Tests | `Layouts/Strip/` (`StripColumnsTests`, `StripLayoutTests`, `WindowSizeTests`), `WorkspaceTests+View`, `ScrollPlanTests`, `ViewScrollTests`, `SwipeSessionTests` (TylerCore); `StripScenarios`, `StripSwipeScenarios` (TylerScenarioTests) |

## Known issues and edge cases

Each is a GitHub issue labelled `strip`, which holds the details.

- [#29](https://github.com/dhansmair/tyler/issues/29) Strip: quarters pair by list order, so swaps and new windows split a pair
- [#30](https://github.com/dhansmair/tyler/issues/30) Strip: resizing with the mouse isn't built
- [#31](https://github.com/dhansmair/tyler/issues/31) Strip: swap by drag only works between windows in view
- [#32](https://github.com/dhansmair/tyler/issues/32) Strip: no rubber band at the ends
- [#33](https://github.com/dhansmair/tyler/issues/33) Strip: half columns differ by a point between the two halves of the view
- [#34](https://github.com/dhansmair/tyler/issues/34) Strip: windows leaving on the left show briefly beside a left Dock
- [#35](https://github.com/dhansmair/tyler/issues/35) Strip: scrolls with several displays (parking on the left, sliding over a neighbour)
- [#36](https://github.com/dhansmair/tyler/issues/36) Strip: focus follows mouse can scroll the strip
- [#37](https://github.com/dhansmair/tyler/issues/37) Strip: older tylerd builds can't read a state file naming the strip

## Not yet checked against real windows

- [#41](https://github.com/dhansmair/tyler/issues/41) Strip: checks against real windows still to do

## Open design questions

- [#38](https://github.com/dhansmair/tyler/issues/38) Strip: explicit columns or a stack command instead of list-order quarters
- [#39](https://github.com/dhansmair/tyler/issues/39) Strip: column widths of ⅓ and ⅔
- [#40](https://github.com/dhansmair/tyler/issues/40) Strip: spill a swipe over to the next workspace at the strip's end
