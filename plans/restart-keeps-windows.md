# Restart keeps the windows where they are

## Context
`tyler restart` is `stop` then `start`. `stop` sends SIGTERM, and tylerd puts every window back where it was before it first moved it, parked ones included. The new tylerd then sees every window as new and tiles them all onto workspace 1. So each restart (needed after every rebuild) throws away the user's workspace arrangement. The user asked for a restart that keeps it.

## Decisions
- Agreed with the user: **restart keeps everything in place.** `stop`, Ctrl-C and SIGTERM keep putting windows back (the undo stays the safety net).
- **Hand-over through a state file.** On restart tylerd writes `~/.tyler/tyler.state.json` (next to the socket, like the log: `<socket without .sock>.state.json`) and exits without moving any window. The new tylerd reads it once at start and deletes it once windows are tracked. The file is written exactly when tylerd exits without restoring windows, so whenever it exists it describes where tylerd left them; it can't go stale in a harmful way.
- **Windows are matched by `CGWindowID`**, which stays the same while the window lives. Windows that closed in between are dropped; new ones are handled as usual (they join the current workspace).
- **Saved:** per workspace the window list, focused window, layout and master ratio; the current workspace; floated windows; tiling on or off; each window's original frame (so a later `stop` still puts windows back where they were before tylerd first moved them). Gaps come from the config, not the file. A `version` field; an unknown version is ignored with a log line.
- **The signal is SIGUSR1** (SIGTERM keeps meaning "restore"). A tylerd from before this change would die on SIGUSR1 without cleaning up, so `ServerStatus` says whether the server understands it (`keepsWindowsOnRestart`, optional so old servers decode as "no"); against an old server, restart falls back to SIGTERM.

## Increments (one commit each)
1. TylerCore: `SavedState` (Codable, built from and applied to a `WorkspaceStack`), `Paths.statePath`, reading and writing the file. Tests.
2. TylerServer: `WindowManager` can hand over (finish any slide, return a `SavedState`, leave windows alone) and start from a `SavedState`. Tests: arrangement, focus, layouts, floated and original frames survive; closed windows are dropped; nothing moves on start.
3. tylerd and client: SIGUSR1 writes the file and exits; launch reads it and deletes it once tracking; `ServerStatus.keepsWindowsOnRestart`; `DaemonController` restart uses SIGUSR1 when supported. Tests with the fake daemon system.
4. Docs (manual: restart; roadmap), then a real restart checked with `devtools/live-check`.
