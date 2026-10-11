# Strip layout: current state

> **Experimental.** The strip layout is built, unit tested and merged into `main`, and the user has
> tried it on real windows. Its design isn't settled yet (quarters in particular), several edge
> cases aren't handled, and some behaviour hasn't been checked against real windows. Expect it to
> change. The other layouts don't depend on it.

This file describes the strip as it is now. `plans/strip-layout.md` is the plan it was built from
(with the decisions and the detailed design at the time), and the "Strip layout" section in
`devdocs/ROADMAP.md` holds the checklist. Keep this file current when the strip changes.

## What it is

A niri-like layout. A workspace's windows form one long row of columns, left to right in list
order, and the display shows a view of that row: as many whole columns as fit. Focusing a window
out of view scrolls the row, and so does a 3-finger swipe. It's `LayoutKind.strip`, shown as `↔`
in the menu bar, and `tyler layout next` cycles tall → full → strip.

## Behaviour

### Sizes and columns

Each window has a size (`WindowSize`), set with `tyler size half|full|quarter|next`:

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
- `size quarter` **pairs**: it makes the next window `quarter` too, or the previous one if the
  next already shares a column or there is none. With neither free it is an error.
- Leaving a pair puts the mate back to `half`. That happens on another size, closing, floating,
  minimizing, or moving the window to another workspace (it arrives there as `half`).
- Sizes are kept in every layout (`tall` and `full` ignore them) and survive `tyler restart`. A
  window forgets its size when it leaves tiling.

### The view

- The view is stored as the first window of its leftmost column (`Workspace.firstVisible`), not
  in points, so it survives gap, display and Dock changes.
- After every change (focus, insert, remove, swap, size), the view moves the least distance that
  shows the focused window's column whole. It never shows empty space past the strip's end when
  one more column on the left would fit.
- With only ½ and full widths, the view always starts at a column boundary. If the next column
  doesn't fit (a full column after a half one), the rest of the view stays empty rather than
  showing part of a column.
- The view survives `tyler restart`.

### Windows out of view

- Windows out of view **park at the right edge** of the display, like the windows of other
  workspaces, because macOS won't take a window further off screen. A window counts as in view
  when its frame's centre is inside the visible area.
- They stay on their workspace even when the parked frame lies mostly on a display to the right.
- They don't move when you switch workspaces (only windows in view slide), and `tyler tiling off`
  brings them back to where they were before tylerd moved them.

### Scrolling

- `focus`, `swap`, `size`, and a click or cmd-tab on a window out of view **slide** the strip to
  the new view (`ScrollPlan`).
- Windows coming in from the right start where they are parked. Windows leaving on the left stop
  at the edge (1 point visible, or a 56-point strip beside a left Dock), then park.
- Windows out of view at both ends of a scroll stay parked.
- The focus event a scroll causes doesn't interrupt it.

### Swiping

- On a strip workspace, the 3-finger swipe **scrolls the strip and never switches workspaces**,
  even when every window fits (decided with the user). Leaving a strip workspace takes
  `tyler workspace`.
- When the pan begins, the views it can rest at are worked out (`StripScroll`). The windows follow
  the fingers along the scroll between the two views the position lies between.
- On release, `Snap` picks a view: the nearest one, or the next one for a flick. If the focused
  window left the view, the nearest window in view gets focus.
- A pan that hasn't left its first view moves nothing. At the strip's ends the content just
  stops.
- A command in the middle of a pan puts the windows back where they were.

## Code map

| Piece | Where |
|---|---|
| `WindowSize`, `StripLayout`, `StripColumns` (packing, fit, end clamp, snap points), `StripGeometry` | `Sources/TylerCore/StripLayout.swift` |
| `LayoutInput.sizes`, `LayoutInput.firstVisible`, `LayoutKind.strip` | `Sources/TylerCore/Layout.swift` |
| Sizes, pairing (`setSizeWithPartner`), the view (`firstVisible`, `refitView`, `scroll(toFirstVisible:)`), `stripViews` | `Sources/TylerCore/Workspace+Strip.swift` |
| `arrangement`, `placements` (in view only), `offView`, `restingPlacements` | `Sources/TylerCore/Workspace.swift` |
| `ScrollPlan` (one scroll between two arrangements) | `Sources/TylerCore/ScrollPlan.swift` |
| `StripScroll` (a pan: views, positions, segments) | `Sources/TylerCore/StripScroll.swift` |
| `CGRect.shows(_:)` (the in-view rule) | `Sources/TylerCore/Geometry.swift` |
| Sizes and view in the state file (optional fields) | `Sources/TylerCore/SavedState.swift` |
| `tyler size`, scrolls (`stripSnapshot`, `scrollIfViewMoved`), swipes | `Sources/TylerServer/WindowManager+Strip.swift` |
| `PanTarget.strip`, dispatch of pans | `Sources/TylerServer/WindowManager+Pan.swift` |
| Parking in `applyLayout`, focus scrolls | `WindowManager.swift`, `WindowManager+Workspaces.swift` |
| Tests | `StripLayoutTests`, `StripViewTests`, `ScrollPlanTests`, `StripScrollTests` (TylerCore); `StripTests`, `StripPanTests` (TylerServer) |

## Known issues and edge cases

- **Quarters feel odd** to the user, even with pairing. Pairs follow from list order rather than
  being real columns, so:
  - `swap` can split a pair (each half then shows like `half`);
  - a new window inserted between the two breaks the pair the same way.
- **Mouse resizing** isn't built for the strip: dragging an edge snaps back.
- **Swap by drag** only works between windows in view.
- **No rubber band** at the strip's ends.
- **Half columns differ by a point** between the left and right half of the view (rounding, so a
  view matches `tall` exactly). A window that stays in view while moving from one half to the
  other is resized by that point during a scroll.
- **Leaving on the left** shows the window briefly beside a left Dock before it parks, the same as
  the workspace slide.
- **Several displays (M5):** parking at the right edge is unsolved there in general; the strip
  adds more parked windows.
- **Focus follows mouse** (`plans/focus-follows-mouse.md`, not built) would scroll the strip when
  the pointer crosses into a partly visible window mid-scroll. Check the two together if both
  exist.
- **Switching builds:** a `tylerd` from before the strip can't read a state file that names the
  strip layout and starts afresh, which can leave windows parked. Use `tyler stop` and then
  `tyler start` rather than `restart` when going back.

## Not yet checked against real windows

- Windows leaving on the left beside a left Dock, then parking
- A slow app (Firefox) during a scroll and a swipe
- `tyler restart` keeping the view and the sizes
- `quarter` windows against apps' minimum heights (macOS clamps them, and the column won't line up)
- A click on a parked window's 1-point sliver scrolling to it

## Open design questions

- **Quarters:** replace the list-order pairing with explicit columns, or with a stack command
  ("stack with next" / "unstack")?
- **Widths:** only ½ and full now; ⅓ and ⅔ (niri's defaults) would make partly visible
  neighbours common, which parking can't show at rest.
- **Leaving a strip workspace by swipe:** the swipe stays inside the strip now. Spilling over to
  the next workspace at the strip's end is an option if a key turns out to be too clumsy.
