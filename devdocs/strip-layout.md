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

- **Quarters feel odd** in use, even with pairing. Pairs follow from list order rather than
  being real columns, so:
  - `window swap` can split a pair (each half then shows like `half`);
  - a new window inserted between the two breaks the pair the same way.
- **Mouse resizing** isn't built for the strip: dragging an edge snaps back.
- **Swap by drag** only works between windows in view.
- **No rubber band** at the strip's ends.
- **Half columns differ by a point** between the left and right half of the view (rounding, so a
  view matches `tall` exactly). A window that stays in view while moving from one half to the
  other is resized by that point during a scroll.
- **Leaving on the left** shows the window briefly beside a left Dock before it parks, the same as
  the workspace slide.
- **Several displays (M5):** each display parks at an edge with no neighbour, the left one when
  another display lies to the right. Two things the strip doesn't handle yet there:
  - on a display that parks on the left, windows out of view to the right still wait at the left
    edge, so a scroll that brings one in makes it jump from the left edge to the right before it
    slides in;
  - the strip's scrolls (`ScrollPlan`) don't follow the workspace slide's rule that nothing
    slides onto a neighbour: a window scrolling out towards another display still hangs over it
    on the way.
- **Focus follows mouse** focuses a partly visible window the pointer rests on, which scrolls the
  strip to show it whole. It may also scroll the strip when the pointer crosses into a window
  mid-scroll (only windows in view count, but a scroll moves the view). Neither is checked.
- **Switching builds:** a `tylerd` from before the strip can't read a state file that names the
  strip layout, and one from before state file version 3 can't read version 3; either starts
  afresh, which can leave windows parked. Use `tyler stop` and then `tyler start` rather than
  `restart` when going back.

## Not yet checked against real windows

- Windows leaving on the left beside a left Dock, then parking
- A slow app (Firefox) during a scroll and a swipe
- `tyler restart` keeping the view and the sizes
- `quarter` windows against apps' minimum heights (macOS clamps them, and the column won't line up)
- A click on a parked window's 1-point sliver scrolling to it
- A partly visible window during a swipe, a click on it, and parked beside a display on the right
  (at rest and scrolling by focus are checked)

## Open design questions

- **Quarters:** replace the list-order pairing with explicit columns, or with a stack command
  ("stack with next" / "unstack")?
- **Widths:** only ½ and full now; ⅓ and ⅔ (niri's defaults) would make partly visible
  neighbours common. They show at an edge without a neighbouring display, and park at one with.
- **Leaving a strip workspace by swipe:** the swipe stays inside the strip now. Spilling over to
  the next workspace at the strip's end is an option if a key turns out to be too clumsy.
