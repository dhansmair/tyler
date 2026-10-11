# Indicators target and the workspace map

## Context
The menu bar item shows `1 [2] 3 4  ▥`: you can tell which workspace you're on, but not what's on each one. The user wants a second item next to it: a small map of the row, with one thumbnail per workspace and a small gap between them, a rectangle (white in a dark menu bar) for each tiled window placed as its layout places it, the active workspace highlighted and the focused window bordered in another colour.

Today one indicator is spread over three targets: `IndicatorState` (TylerCore), `updateIndicator` and the `Indicator` protocol (TylerServer), `StatusBarIndicator` (TylerPlatform). The user asked for indicators to be isolated behind a common interface, in a **separate target**. So this plan first moves the existing indicator into a new `TylerIndicators` target with no change in behaviour, then adds the map as a second indicator. Adding the map then leaves the server untouched, apart from the snapshot getting the display area.

Decisions (with the user, 2026-10-11):
- A new SwiftPM target `TylerIndicators` holds everything indicator-specific: models, drawing, menus, clicks.
- Active workspace: a **thin rounded outline** around its thumbnail. Windows are equally bright on every workspace.
- Click on the map: a **left click on a thumbnail switches** to that workspace (`workspace <n>`); a **right click (or ctrl-click) opens the same menu** as the text item (decided 2026-10-11). The menu's model and its `NSMenu` building are shared by both items.
- Focused window: a **clearly visible blue border** (`controlAccentColor`, blue by default, 1.5 pt).
- Config: a new `[indicator]` section with `text = true` and `map = true`, applied by `tyler reload`.

Decisions for review:
- **The focused window is the current workspace's `Workspace.focused`** (the last tiled window used). Focusing a floated window or dialog doesn't move the border. Other workspaces show no focus.
- **In `full`, all windows share one frame**, so the thumbnail shows one rectangle.
- **An empty workspace** shows only its faint slot.

## Architecture

```
TylerCore         IndicatorSnapshot (value) + Indicator protocol      ← the common interface
TylerServer       builds the snapshot, calls indicator.show(snapshot)  (knows nothing else)
TylerIndicators   (new) depends on TylerCore only; imports AppKit
                  models:  TextTitle, IndicatorMenu, WorkspaceMap     ← pure, unit tested
                  AppKit:  TextIndicator, MapIndicator, IndicatorGroup, NSMenu builder (shared)
TylerPlatform     Accessibility and the other system code only (StatusBarIndicator moves out)
tylerd            creates IndicatorGroup([TextIndicator, MapIndicator]) and passes it to the manager
```

- **`IndicatorSnapshot`** (TylerCore, `Equatable, Sendable`) holds `row: WorkspaceRow`, `tiling: ServerStatus.Tiling`, `area: CGRect?` (the primary display's visible frame) and `settings: Config.Indicator`. It is raw state: no titles, no symbols.
- **`protocol Indicator: AnyObject { @MainActor func show(_ snapshot: IndicatorSnapshot) }`** moves from `TylerServer/WindowBackend.swift` to TylerCore, so TylerIndicators doesn't need TylerServer and the server never sees AppKit.
- **Redraw dedup moves into each indicator.** The server pushes the snapshot whenever it changes (`shownIndicatorState` becomes `shownSnapshot`). Each indicator derives its model and redraws only when that model changed, so a drag that only changes row weights doesn't repaint the text item.
- **The way back is unchanged:** each indicator gets `perform: @MainActor (Request) -> Void`, wired in `tylerd/main.swift` as today (`indicatorTarget`).
- **The new target can be unit tested.** The "not unit tested" rule exists because of Accessibility and live windows, not AppKit. Tests cover the pure models. The `NSStatusItem` classes stay thin.

## Increments (one commit each, `make check` green)

### 1. Move the indicator into `TylerIndicators` (refactor, no behaviour change)
- Before the move, check that `IndicatorStateTests` and `IndicatorTests` cover the title, the menu and the redraw rule. Add any missing test in a commit of its own.
- `Package.swift`: add `.target(name: "TylerIndicators", dependencies: ["TylerCore"])` and `.testTarget(name: "TylerIndicatorsTests", dependencies: ["TylerCore", "TylerIndicators"])`. Add `TylerIndicators` to `tylerd`'s dependencies.
- Add `IndicatorSnapshot` and the `Indicator` protocol to TylerCore. `WindowManager+Indicator.updateIndicator()` builds the snapshot (`area: primaryDisplay?.visibleFrame`, `settings: config.indicator`) and calls `show` when it changed.
- Split `IndicatorState` into TylerIndicators: `TextTitle` (title parts, the layout symbol, the notice) and `IndicatorMenu` (menu items), both built from a snapshot. Move `StatusBarIndicator` there as `TextIndicator`, with the `NSMenu` building moved into a helper the map will share.
- Move `Tests/TylerCoreTests/IndicatorStateTests.swift` to `Tests/TylerIndicatorsTests/` with the same assertions; only the setup changes, to build a snapshot.
- Server `IndicatorTests` and `FakeIndicator` record snapshots, and their assertions read the snapshot. `Config.Indicator` arrives in increment 4, so the snapshot has no settings until then.
- Update the docs: the CLAUDE.md layout section, plus a ROADMAP note under "Menu bar indicator".

### 2. `WorkspaceMap` model + tests
- `WorkspaceMap { size; thumbnails: [Thumbnail] }`, `Thumbnail { frame; windows: [CGRect]; focusedIndex: Int?; isCurrent; isEmpty }`, built from a snapshot.
- Thumbnails are 14 pt high, with the display's aspect ratio (16:10 when no display is known) and 4 pt between them. If the row would be wider than about 200 pt (with 10 workspaces), the height shrinks.
- Window rectangles reuse the real layouts: copy each `Workspace`, call `setGaps(inner: 1, outer: 1)`, then `placements(in: thumbnailRect)` (`Workspace.swift`). The ratio and row weights carry over, and future layouts work without changes.
- Every rect is rounded to whole points, so the map only redraws when it visibly changes.
- `workspaceIndex(at:)` does hit-testing. A point in a gap goes to the nearest thumbnail.
- Tests (parameterized where possible): frames and gaps, tall with 1/2/3 windows, full, the focused index, the current and empty flags, rounding, the width cap, and hit-testing including gaps and points outside.

### 3. `MapIndicator`
- An `NSStatusItem` whose button shows an `NSImage(size:flipped:drawingHandler:)`. It isn't a template image, so the accent colour survives, and the colours resolve per appearance:
  - windows: `labelColor`
  - empty slots and the active outline: `tertiaryLabelColor` (1 pt, radius 2)
  - the focused window's border: `controlAccentColor` (blue by default), 1.5 pt, drawn on top so it stays visible against the white rectangles
- Clicks: the item's `menu` property stays **unset**, because an `NSStatusItem` with a menu opens it on every click and never calls the button's action. Instead `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`, and the action reads `NSApp.currentEvent`:
  - right click or ctrl-click: build the shared menu and pop it up under the item (`statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil`, the usual trick, so it looks like a normal status item menu)
  - left click: convert the point to image coordinates (the image is centred in the button), call `map.workspaceIndex(at:)`, then `perform(.workspace(.number(i + 1)))`. A click on the current workspace does nothing visible.
- `IndicatorGroup` fans `show` out to its members. `tylerd` creates the map item after the text item, so the map sits to the left of the text.

### 4. `[indicator]` config
- `Config.Indicator { text = true; map = true }` is parsed with the `Setting` helpers in `Config.swift`, with parsing tests. Each indicator sets its item's `isVisible` from `snapshot.settings`, so `reload` applies the change at once.
- Update `docs/manual.md` and `~/.config/tyler/tyler.toml` (see memory: sync personal tyler.toml).
- Add a ROADMAP section "Workspace map" with the checklist below, and update the CLAUDE.md status line.

## Verification
- Run `make check` after every increment. After increment 1, also check that `git diff --stat Tests` shows only the moved file and setup changes.
- Run `make build && tyler restart`. `devtools/live-check menubar` should show the text item unchanged after increment 1, and both items after increment 3 (live-check reads text only, so the map needs the user's eyes).
- Check by hand and tick off in ROADMAP:
  - The map matches `tyler list` for tall with 1, 2 and 3 windows, and for full.
  - The outline follows `workspace next`.
  - The focus border follows `focus next`.
  - `ratio +0.05` and a mouse resize update the map.
  - A left click on each thumbnail switches to that workspace; a right click and a ctrl-click on the map open the menu, placed like the text item's; the text item's menu still works.
  - Light and dark menu bars both look right.
  - `tiling off` hides the map.
  - `[indicator] text = false` followed by `reload` hides the text item.
  - 10 workspaces fit.
