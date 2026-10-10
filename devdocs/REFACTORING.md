# Refactoring backlog

Coding agents tend to add features on top of each other and rarely refactor, which slows later work down. This file keeps track of refactorings and performance improvements found by reviewing the whole codebase (October 2026, after the trackpad swipe landed). Nothing here changes behaviour on purpose.

## How to work through it

- **One item (or one step of an item) per commit**, like any other increment. Tick it off here and add a line to the log at the end in the same commit.
- **Pin behaviour down first.** If the tests don't clearly cover what a refactoring touches, add regression tests in a commit of their own *before* changing the code, so the refactoring commit changes no tests (or only their setup).
- **Run `live-check`** after any item that changes how or when windows move (marked **[live]**).
- Items name files and symbols, not line numbers, since the code keeps moving. Check that a finding still holds before starting it.
- Ranking = payoff (speed of future work, or speed for the user) against risk. **[perf]** marks performance items.

Sizes: XS < 20 lines, S < 60, M < 200, L larger.

## Tier 1: do soon

- [x] **1. [perf] [live] Stop the event echo storm.** `AXBackend.setFrame` reads the window back (about 7 AX reads plus an `NSRunningApplication` lookup) and yields `.updated`. The app's own moved/resized notification then produces a second `.updated`. Every `.updated` goes through `WindowManager.apply` → `reconcile` → `syncWorkspaces`, a full sync of every workspace, even though a plain move changes nothing in the lists.
  - Cost: a retile of 8 windows means about 16 syncs and over 100 AX calls. A slide of 6 windows × 30 steps means about 180 syncs and 1,200 reads on the main actor that also runs the animation. This is the likely cause of jumpy slides and swipes with slow apps.
  - Fixes:
    - [x] Give `.updated` a fast path that skips `reconcile` unless something tiling-relevant changed (tileable, minimized, fullscreen, *display*: a window moved to another display must still leave the workspace). Done in `WindowManager.apply`/`mayChangeLists`. One behaviour change: a window left out while no display was connected used to be picked up by its next move; now it waits for the next event of another kind (focus, create, a command).
    - [x] Drop the read-back in `setFrame`, or read only the frame (it exists to report clamped sizes). Done the middle way: `setFrame` reads back only the frame (2 AX reads instead of 7) and reuses the rest of the window's last full read. Checked on real windows (macOS 26.7, 2026-10-11): after `retile`, a workspace round trip and `layout full`/`tall`, `tyler list` matched `live-check stacking`, including Ghostty windows that snap to character cells.
    - [x] Skip the sync for windows that are sliding or panning: covered by the fast path, since a slide step doesn't change tileability and changes display at most once.
  - Before: add tests for the fast path, including the display-change case. M, medium risk. `WindowManager.swift`, `WindowManager+Sync.swift`, `TylerPlatform/AXBackend.swift`.
- [x] **2. Put slide, pan and drag into one interaction state.** `WindowManager` has 27 stored properties. Six of them (`animation`, `animationCount`, `pan`, `panThrottle`, `drag`, `dragThrottle`) describe things that never happen at the same time, and guards like `animation == nil, pan == nil` repeat throughout `+Mouse`, `+Pan` and `+Workspaces`.
  - [x] Step 1 (S, low risk): a `Throttle` type replaces the two identical sleep-then-retry loops (`placePan` in `+Pan`, `followPendingFrame` in `+Mouse`), and each throttle lives inside its session (`PanSession`, `MouseDrag`).
  - [x] Step 2 (M, medium risk): `enum Interaction { case idle, sliding(…), panning(PanSession), dragging(MouseDrag) }`. Watch the transitions: a released pan becomes a slide (`endPan` → `animate`), and `endDrag` moves the preview window back.
  - Worth doing before the strip layout adds a second pan target.
- [x] **3. One source of truth for commands.** A command is spelled out by hand in `Request` (`Protocol.swift`), the parse switches in `TylerClient/CommandLine.swift`, its usage text, `docs/manual.md`, and the "CLI target" block in the roadmap. On the server, dispatch goes `CommandRouter.handle` → `WindowManager.handle` → `handleTilingRequest`/`handleWorkspaceRequest`, and both of the last two end in `default:`, so the compiler can't flag an unhandled request. The `.ping`/`.status` arms in `WindowManager.handle` are dead code.
  - Fix: a `CommandSpec` table in TylerClient (name, arguments, one-line help, parse) that builds the usage text and does the dispatch; one exhaustive switch in `WindowManager.handle`; a test that every command has a `###` heading in the manual. Drop the roadmap's copy.
  - M, low risk.
- [x] **4. A shared test harness.** `makeStarted`, `spread`, `settle` and `listed` are identical in `TilingTests` and `TilingCommandTests`, with variants in `MouseResizeTests`, `WindowManagerTests`, `ReloadTests` and `DragSwapTests`. `WorkspaceHarness` (in `WorkspaceSwitchTests`) already does all of this, but only the workspace suites use it. `for _ in 0..<30 { await Task.yield() }` appears in 7 files, and `guard case .windows(let w) = manager.windows()` 8 or more times.
  - Fix: move the harness into `Tests/TylerServerTests/Harness.swift` as `ManagerHarness`, with a `settle(until:)` that waits for a condition in place of a counted yield loop.
  - M, low risk, about −150 lines. Do this early: it makes every later refactoring cheaper to test.
  - Done: `Tests/TylerServerTests/Harness.swift` holds `ManagerHarness`, `settle()`, `spread`, `FakeBackend.frame(of:)`/`userMoves` and `WindowManager.listed`/`slots`. `settle()` still yields a fixed number of times, but now in one place; a condition-based wait would make every caller name its condition, which wasn't worth it yet.
- [x] **5. A `WindowBookkeeping` struct.** `floated`, `seen`, `originalFrames` and `pendingFocus` are reset by hand in four places: when a window is destroyed (`apply`), `tearDown`, `restorePending` and `handOver` (`+Restart`). A new field that one of them forgets leaves stale state.
  - Fix: one struct with `forget(_:)`, `init(saved:known:)` and `saved`.
  - M, low risk.

## Tier 2: worth doing

- [ ] **6. [perf] Work out the layout once per drag step.** `followDrag`, `follow` → `Workspace.resize` → `ColumnLayout.resize`, and `previewDrop` → `dropTarget` each call `placements(in:)`/`frames(in:)`, 2 to 4 times per event at mouse rate (60–120 Hz). `followDrag` lays out the whole workspace even for echoes from windows that aren't being dragged.
  - Fix: pass the placements along (`dropTarget(in placements:)`); return early for windows that aren't being dragged; cache the dragged slot's frame in `MouseDrag` and check it before `dropTarget`.
  - S, low risk.
- [ ] **7. [perf] Mutate the current workspace in place.** `WorkspaceStack.current` and its subscript use `get`/`set`, so every `workspaces.current.x(…)` and `workspaces[i].sync(…)` copies the windows array (once per drag step, once per workspace per sync).
  - Fix: `_modify { yield &workspaces[currentIndex] }`.
  - XS, low risk.
- [ ] **8. [perf] [live] Fewer AX calls per move.** `AXBridge.setFrame` writes size, then position, then size again (on purpose, for apps that clamp), even when the size already matches, which is common for swaps and the end of a slide. `windowInfo` makes 7 separate reads.
  - Fixes:
    - Use `setPosition` when only the origin changes.
    - Batch the reads with `AXUIElementCopyMultipleAttributeValues`.
    - Cache role/subrole per window and app name/bundle id per process.
  - Batching also shortens stalls on a hung app: `messagingTimeout` is 1 s *per call*, so today one event can block the main actor for about 7 s.
  - M, medium risk.
- [ ] **9. Move the pure logic into TylerCore.**
  - The decision half of `syncWorkspaces` (`+Sync`, at 48 lines the longest function in the server): which windows each workspace should hold, what's new, and the focused arrival. Extract it as `WorkspaceSync.plan(…)`; the server keeps only the parking.
  - `SlidePlan` and `slidePlan(to:direction:on:)` (`+Workspaces`/`+Pan`) need only frames and a display.
  - `isClose`/`isResized` (CGRect geometry), `side(of:)` in `+Pan`, `direction(of:from:to:)` in `+Workspaces`.
  - Makes item 1 easier to test. M, medium risk (tests exist).
- [ ] **10. Small server helpers.**
  - `primaryDisplay`, `currentPlacements()` and `slot(of:)`: `displays.displays.first` appears 9 times, `placements(in:).first(where:)` 4 times.
  - `isTiling`: `state == .running` (usually with `tilingEnabled`) appears about 15 times, and `canFollow` repeats `followDrag`'s guard.
  - `outcome(failures:success:)`: see the third bug below.
  - `place` (`+Placement`) and `restoreOriginalFrames` (`+Workspaces`) are the same loop; merge them in `+Placement`.
  - S, low risk. These helpers are also where the caches in item 13 go.
- [ ] **11. Make adding a layout easier.**
  - Step 1 (S): adding a layout touches 4 places (a type, a `LayoutKind` case, the `LayoutKind.layout` switch, the symbol in `IndicatorState.title`), but the comment in `Layout.swift` says 2. Move the symbol onto `LayoutKind`, rename `LayoutKind.layout` (call sites read `layout.layout`), fix the comment. Merge `ColumnLayout.minimumShare` with `LayoutParameters.ratioRange` (both are the 10% rule).
  - Step 2 (M, medium risk): `TallLayout` converts the pixel widths from the generic `ColumnLayout.Resize` into `mainRatio` (`widths.count == 2`); the next column layout would have to repeat that. Have `ColumnLayout` take column weights in and give them back.
  - Step 3 (L, medium risk): `LayoutParameters` mixes per-workspace state (`mainRatio`, `rowWeights`) with global gaps, which is why `setGaps` is pushed into every workspace. Pass a separate `LayoutGaps` to `frames`.
- [ ] **12. Table-driven config parsing.** Each section in `Config.swift` (Gaps, Gestures, Mouse, Workspaces) repeats the same steps: check it's a table, a switch over sorted keys, a hand-typed list of unknown keys that can drift from the cases, and range checks formatted one by one.
  - Fix: a section helper built from a `[key: reader]` dictionary, with typed readers (`int(in:unit:)`, `bool()`, `number(in:)`). About 110 lines become 50, and each new key becomes one line. Keep the error wording (tests check it).
  - M, low to medium risk.
- [ ] **13. [perf] Cache displays and group indicator updates.**
  - `SystemDisplayProvider.displays` reads and converts `NSScreen.screens` on every call, several times per event. Cache them and refresh on `didChangeScreenParametersNotification`.
  - `updateIndicator` hangs off `didSet` on `workspaces`, so every in-place mutation (one per workspace per sync) builds an `IndicatorState` to compare. Update once at the end of `apply`/`handle` instead.
  - S, low risk.

## Tier 3: tidy-ups

- [ ] **14. Naming.**
  - The workspaces are a row now, but the code still says stack: `WorkspaceStack` → `WorkspaceRow`, along with `init(stack:)` (`IndicatorState`, `SavedState`), `stack(count:keeping:)`, and comments such as "top of the stack first" and "added empty at the bottom". The JSON format has no `stack` field, so it doesn't change. Keep "stack" in `Layouts.swift`, where it is xmonad's word for Tall's right column.
  - CLAUDE.md bans "monitor": `PointerMonitor` (and `monitor`, `monitorLog` in devtools) mean an AppKit event monitor, but rename them anyway (for example `GlobalPointerInput`). `docs/manual.md` says "an external monitor": use "display".
  - M, mechanical.
- [ ] **15. Thinner `tylerd/main.swift`** (167 lines). Move into libraries: loading the config with a fallback to defaults, reading the handed-over state, building `ServerStatus` from the binary's modification time, and the permission poll (as `manager.waitForPermission()`, testable with `FakeGate`). The doc comment above `forgetHandedOverState` describes the poll; fix it.
  - M, low risk.
- [ ] **16. Docs size.**
  - The CLAUDE.md status paragraph is one line of over 2,000 characters that repeats the roadmap. Cut it to 2–3 sentences that point at the roadmap.
  - Move finished milestones out of `ROADMAP.md` (257 lines, about 6,200 words) into `devdocs/roadmap-done.md`.
  - S.
- [ ] **17. Dead code and the public surface.**
  - Unused: `SlidePlan.direction`, `WindowRegistry.count` (tests only), and `_ = task` in `IPCServer.runBlocking`.
  - Public without need: `Parking.visibleSliver`, `Track.init`, `ScrollDirection.outgoingOffset`, `Config.*Range`, `LayoutParameters.withGaps`/`setMainRatio`, `Snap.resisted`. Check `PanRecognizer`'s public properties again now that `SwipeTap` uses it.
  - Narrow these to internal; tests use `@testable`. XS.
- [ ] **18. LiveCheck reuses the AX code.** `devtools/LiveCheck/main.swift` re-implements `AXBridge` reads, `DisplayGeometry.axRect`, and decoding `tyler list --json` with `JSONSerialization` rather than `WindowInfo`. Its tyler path is hard-coded to `debug`.
  - Fix: make it an SPM target that shares a `package`-visible AX module.
  - M, medium risk (changes how live-check builds).
- [ ] **19. Small duplicates.** XS each.
  - `Workspace`/`WorkspaceStack`: wrap-around index math (3×) and insert-after-focus (2×).
  - `Animation.swift`: clamping to 0…1 (4×).
  - `Paths`: the `.sock` stripping (`dropLast(5)`) and the env override.
  - `UnixSocket`: the sockaddr setup and the "save errno, close, throw" block.
  - `DaemonController`: the probe switch (3×) in `statusReport`, `start` and `stop`.
  - `SavedWorkspace` conversion (2×).
  - `FakeBackend`: shared lookup in `setFrame`/`setPosition`.
  - Magic numbers: the 1-point tolerance, `0x0A` in two files, `1 << 20`, `1e-9`.
- [ ] **20. Build tooling and test files.** XS.
  - A `make lint` target that pre-commit calls.
  - Move the `ResponseFormatter` tests out of `CommandLineTests`.
  - Parameterize the ping/list/reload parse tests and the "rejects extra arguments" tests.
  - Share `makeSocketPath`/`makeTempSocketPath` and `makeWorkspace`/`ids` within each test target.

## Bugs found along the way

Not refactorings, but found in the same review. Fix each with a regression test.

- [ ] `setTiling` doesn't go through `beginCommand`, so `tyler tiling on` answers "tiling on" while tylerd is still waiting for Accessibility permission.
- [ ] `focusCurrentWorkspace` only logs a failed focus, so `workspace` and `move-to-workspace` report success when the focus failed.
- [ ] `failures == 0 ? .message(x) : outcome(failures:)` (`setLayout`, the workspace commands) drops the success text when a placement fails ("workspace 3" disappears), while `reload` adds the failures to its message. Pick one.

## Considered and not worth it

So nobody tries them again without a profile that says otherwise:

- An index for the linear `index(containing:)`, `contains` and `slot(of:)` scans. A workspace holds at most about 30 windows, and keeping an index in step on every change is riskier than the microseconds it would save. One AX call costs milliseconds.
- Animation tracks: `Track.position` and the `Animator` loop already allocate nothing per frame.
- Shared `JSONEncoder`/`JSONDecoder` instances and the O(n²) newline search in `UnixSocket.readLine`: both run once per CLI command.

## Log

- 2026-10-11: backlog created.
- 2026-10-11: item 4 done (shared server test harness).
- 2026-10-11: item 5 done (`WindowBookkeeping`), after regression tests for reused window ids.
- 2026-10-11: item 2 step 1 done (`Throttle`, held by `PanSession` and `MouseDrag`).
- 2026-10-11: item 2 step 2 done (`Interaction`), after tests for how slide, pan and drag exclude each other.
- 2026-10-11: item 3 done (`CommandSpec` table, manual check, request switches without `default:`; one switch over every case exceeds SwiftLint's complexity limit, so the split stays).
- 2026-10-11: item 1, server half done (updates that can't change the lists skip the sync); the AX read-back is left for a live check.
- 2026-10-11: item 1 done: `setFrame` reads back only the frame; checked with live-check.
