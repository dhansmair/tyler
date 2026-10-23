# Refactoring backlog

Coding agents tend to add features on top of each other and rarely refactor, which slows later work down. This file keeps track of refactorings and performance improvements still to do. Nothing here changes behaviour on purpose. Done items are deleted (git keeps them); bugs are GitHub issues (`known-issues.md` lists them).

## How to work through it

In progress: none.

- **Where items come from:** after every feature, the agent that built it re-reads the feature's whole diff for refactorings (see "Review a feature once it works" in CLAUDE.md). Small finds are done at once; larger ones land here.
- **Claim an item first:** put it on the "In progress" line above (with who is working on it) and commit, so a parallel agent doesn't take it too; clear it when the item is done. See "Parallel agents" in CLAUDE.md.
- **One item (or one step of an item) per commit**, like any other increment. Delete it here in the same commit.
- **Pin behaviour down first.** If the tests don't clearly cover what a refactoring touches, add regression tests in a commit of their own *before* changing the code, so the refactoring commit changes no tests (or only their setup).
- **Run `live-check`** after any item that changes how or when windows move (marked **[live]**).
- Items name files and symbols, not line numbers, since the code keeps moving. Check that a finding still holds before starting it.
- Ranking = payoff (speed of future work, or speed for the user) against risk. **[perf]** marks performance items.

Sizes: XS < 20 lines, S < 60, M < 200, L larger.

## Open

- [ ] **Trim comments that restate the code.** Much of the tree carries explanatory doc comments (see "Comments earn their place" in `coding-guidelines.md`). Go one target at a time, smallest first; rename where a better name makes a comment redundant. Comments only, plus renames: S to M per target, low risk.
- [ ] **Share one listen-only tap type.** `TrackpadGestureListener`, `PointerMoveListener` and `ModifierKeyListener` each repeat creating, adding, enabling and invalidating a listen-only session tap with an unretained pointer to themselves, and `isListening` and `turnBackOnIfOff` on it (`MouseButtonInterceptor` repeats the last two as well). A generic `ListenOnlyTap` that takes the event mask and a handler would hold that once; the per-listener callbacks pick out their Sendable values first. S, low risk.
- [ ] **[perf] Run the mouse button interceptor off the main thread.** `MouseButtonInterceptor` is an active head-insert session event tap on mouse down, drag and up, armed only while a press may be tyler's (`PressTakeover`), and its callback runs on the main thread. A modifier-click or gap press made while the main actor is busy waits for it, or is missed when it comes before the tap is armed, since arming waits for the main thread too; a stall there (an AX call on a hung app, an attach) holds those presses until macOS turns the tap off, about 1 s, and the check every 2 s in `MacPointerInput` turns it back on for the next one. Run the arming and the tap on a thread of its own with a snapshot of what it needs to decide (the modifier, which windows are tiled); or ask the main actor from that thread and pass the press on after a short timeout (about 50 ms), which keeps the decision in one place. After 0.1.0: skipping an app that timed out removed the long stalls, so measure first how often the main thread is held up for more than 100 ms in daily use. Attaching a hung app is one such stall: each of its up to 6 attempts (500 ms apart, a round again whenever it comes to the front) waits up to the 1 s AX timeout on the main thread. L, medium risk. **[live]**

## Considered and not worth it

So nobody tries them again without a profile that says otherwise:

- Building `devtools/LiveCheck` from the package. The tool is standalone on purpose (see the live-check skill): it compiles on its own and can't break the package. Sharing `AXBridge` would add a third executable to every build and pre-commit run, to save about 70 lines of stable AX reads.
- Caching `displays.displays`. It is read a few times per window event, echoes included, but a read takes about 50 µs (one display, measured October 2026): about 75 ms over a drag of several seconds with 500 echoes, against 10 ms for each window it moves. A cache also risks tiling against an old visible frame: it changes when the Dock resizes or hides, and it isn't clear that `didChangeScreenParametersNotification` reports that every time.
- Grouping `updateIndicator` calls. It compares a small snapshot and only redraws on change, it runs rarely, and calling it by hand at the end of each entry point could miss one.
- An index for the linear `index(containing:)`, `contains` and `slot(of:)` scans. A workspace holds at most about 30 windows, and keeping an index in step on every change is riskier than the microseconds it would save. One AX call costs milliseconds.
- Animation tracks: `Track.position` and the `Animator` loop already allocate nothing per frame.
- Shared `JSONEncoder`/`JSONDecoder` instances and the O(n²) newline search in `UnixSocket.readLine`: both run once per CLI command.
